"""Accounts and sign-in.

Two kinds of account:

  * resident  — anyone with an email address
  * township  — an address on a recognised municipal domain (townships.py)

Both must prove control of the mailbox with an emailed six-digit code before the
account works at all. For township accounts that step is the whole basis of
trust: the domain check only says what an address claims to be.

Passwords are stored as salted scrypt hashes; session tokens and verification
codes are stored only as SHA-256 hashes.

Serve this over HTTPS anywhere but a local machine — passwords and tokens are
sent in request bodies and headers.
"""

import hashlib
import hmac
import logging
import os
import re
import secrets
import uuid
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

import storage
import townships

log = logging.getLogger("stormwatch.auth")
router = APIRouter(prefix="/api/v1/auth", tags=["Accounts"])

SESSION_DAYS = 30
CODE_MINUTES = 15
CODE_MAX_ATTEMPTS = 5
CODE_RESEND_SECONDS = 60
MAX_FAILED_LOGINS = 5
LOCKOUT_MINUTES = 15
MIN_PASSWORD_LENGTH = 8
EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def utcnow():
    return datetime.now(timezone.utc)


def iso(moment):
    return moment.isoformat(timespec="seconds")


def sha256(value):
    return hashlib.sha256(value.encode()).hexdigest()


def hash_password(password):
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1)
    return f"scrypt${salt.hex()}${digest.hex()}"


def password_matches(password, stored):
    try:
        _, salt_hex, digest_hex = stored.split("$")
    except (AttributeError, ValueError):
        return False
    candidate = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt_hex), n=2**14, r=8, p=1)
    return hmac.compare_digest(candidate.hex(), digest_hex)


def public_user(user):
    return {"id": user["id"], "email": user["email"], "role": user["role"], "township": user["township"]}


def find_user(email):
    with storage.connect() as conn:
        row = conn.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
    return dict(row) if row else None


def start_session(user_id):
    token = secrets.token_urlsafe(32)
    with storage.connect() as conn:
        conn.execute("INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)",
                     (sha256(token), user_id, iso(utcnow() + timedelta(days=SESSION_DAYS))))
    return token


# --- Request authentication ----------------------------------------------------

def bearer_token(request):
    header = request.headers.get("Authorization", "")
    return header[7:].strip() if header.lower().startswith("bearer ") else ""


def optional_user(request: Request):
    """The signed-in user, or None. Never raises."""
    token = bearer_token(request)
    if not token:
        return None
    with storage.connect() as conn:
        row = conn.execute(
            """SELECT users.* FROM sessions JOIN users ON users.id = sessions.user_id
               WHERE sessions.token_hash = ? AND sessions.expires_at > ?""",
            (sha256(token), iso(utcnow())),
        ).fetchone()
    return dict(row) if row else None


def require_user(request: Request):
    user = optional_user(request)
    if user is None:
        raise HTTPException(status_code=401, detail="Sign in to do that.")
    return user


# --- Verification codes ----------------------------------------------------------

async def deliver_code(email, code):
    """Emails the code through Resend, or logs it when email is not configured.

    The logged fallback exists so the project runs on a laptop with no mail
    provider. It is a development convenience only: a deployment without
    RESEND_API_KEY cannot verify anyone, which is why /health reports it.
    """
    api_key, sender = os.environ.get("RESEND_API_KEY"), os.environ.get("DISPATCH_FROM_EMAIL")
    if not api_key or not sender:
        log.warning("EMAIL NOT CONFIGURED — verification code for %s is %s", email, code)
        return
    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(
            "https://api.resend.com/emails",
            headers={"Authorization": f"Bearer {api_key}"},
            json={"from": sender, "to": [email], "subject": "Your StormWatch NJ verification code",
                  "text": f"Your StormWatch NJ code is {code}. It expires in {CODE_MINUTES} minutes.\n\n"
                          "If you did not ask for this, you can ignore this email."},
        )
        response.raise_for_status()


async def issue_code(user):
    """Creates and sends a fresh code, unless one was sent moments ago."""
    now = utcnow()
    with storage.connect() as conn:
        row = conn.execute("SELECT sent_at FROM email_codes WHERE user_id = ?", (user["id"],)).fetchone()
        if row and datetime.fromisoformat(row["sent_at"]) > now - timedelta(seconds=CODE_RESEND_SECONDS):
            return
        code = f"{secrets.randbelow(1_000_000):06d}"
        conn.execute(
            """INSERT OR REPLACE INTO email_codes (user_id, code_hash, expires_at, attempts, sent_at)
               VALUES (?, ?, ?, 0, ?)""",
            (user["id"], sha256(code), iso(now + timedelta(minutes=CODE_MINUTES)), iso(now)),
        )
    try:
        await deliver_code(user["email"], code)
    except Exception as exc:
        log.error("Could not send verification email to %s: %s", user["email"], exc)
        raise HTTPException(status_code=502, detail="Could not send the verification email. Try again shortly.")


# --- Endpoints -------------------------------------------------------------------

class SignUp(BaseModel):
    email: str
    password: str
    account_type: str = "resident"


class Credentials(BaseModel):
    email: str
    password: str


class Verification(BaseModel):
    email: str
    code: str


class EmailOnly(BaseModel):
    email: str


class GoogleToken(BaseModel):
    id_token: str
    account_type: str = "resident"


def normalise(email):
    return email.strip().lower()


def role_for(email, account_type):
    """Returns (role, township_name) or raises if a township claim is invalid."""
    if account_type == "resident":
        return "resident", None
    if account_type != "township":
        raise HTTPException(status_code=400, detail="account_type must be 'resident' or 'township'.")
    match = townships.township_for(email)
    if match is None:
        raise HTTPException(
            status_code=400,
            detail="That email is not on a recognised township domain. Use your official municipal "
                   "address, or create a resident account instead.",
        )
    return "township", match[0]


@router.get("/township-domains")
def township_domains():
    return [{"domain": domain, "name": name, "county": county}
            for domain, (name, county) in sorted(townships.TOWNSHIP_DOMAINS.items(), key=lambda i: i[1])]


@router.post("/signup")
async def signup(body: SignUp):
    email = normalise(body.email)
    if not EMAIL_PATTERN.match(email):
        raise HTTPException(status_code=400, detail="Enter a valid email address.")
    if len(body.password) < MIN_PASSWORD_LENGTH:
        raise HTTPException(status_code=400, detail=f"Use a password of at least {MIN_PASSWORD_LENGTH} characters.")
    role, township = role_for(email, body.account_type)

    existing = find_user(email)
    if existing and existing["verified"]:
        raise HTTPException(status_code=409, detail="An account with that email already exists. Sign in instead.")

    with storage.connect() as conn:
        if existing:
            # Never verified, so nobody has proved they own it; let the sign-up be redone.
            conn.execute("UPDATE users SET password_hash = ?, role = ?, township = ? WHERE id = ?",
                         (hash_password(body.password), role, township, existing["id"]))
        else:
            conn.execute(
                """INSERT INTO users (id, email, password_hash, role, township, verified, created_at)
                   VALUES (?, ?, ?, ?, ?, 0, ?)""",
                (str(uuid.uuid4()), email, hash_password(body.password), role, township, iso(utcnow())),
            )
    await issue_code(find_user(email))
    return {"status": "verification_required", "email": email}


@router.post("/verify")
def verify(body: Verification):
    user = find_user(normalise(body.email))
    failure = HTTPException(status_code=400, detail="That code is wrong or has expired. Request a new one.")
    if user is None:
        raise failure
    with storage.connect() as conn:
        row = conn.execute("SELECT * FROM email_codes WHERE user_id = ?", (user["id"],)).fetchone()
        if row is None or row["expires_at"] < iso(utcnow()) or row["attempts"] >= CODE_MAX_ATTEMPTS:
            raise failure
        if not hmac.compare_digest(row["code_hash"], sha256(body.code.strip())):
            conn.execute("UPDATE email_codes SET attempts = attempts + 1 WHERE user_id = ?", (user["id"],))
            conn.commit()
            raise failure
        conn.execute("DELETE FROM email_codes WHERE user_id = ?", (user["id"],))
        conn.execute("UPDATE users SET verified = 1 WHERE id = ?", (user["id"],))
    user = find_user(user["email"])
    return {"token": start_session(user["id"]), "user": public_user(user)}


@router.post("/resend")
async def resend(body: EmailOnly):
    user = find_user(normalise(body.email))
    if user and not user["verified"]:
        await issue_code(user)
    # Same answer either way, so this cannot be used to test which emails have accounts.
    return {"status": "sent"}


@router.post("/login")
async def login(body: Credentials):
    email = normalise(body.email)
    user = find_user(email)
    wrong = HTTPException(status_code=401, detail="Incorrect email or password.")
    if user is None or not user["password_hash"]:
        raise wrong
    if user["locked_until"] and user["locked_until"] > iso(utcnow()):
        raise HTTPException(status_code=429, detail="Too many attempts. Try again in a few minutes.")

    if not password_matches(body.password, user["password_hash"]):
        failed = user["failed_logins"] + 1
        locked = iso(utcnow() + timedelta(minutes=LOCKOUT_MINUTES)) if failed >= MAX_FAILED_LOGINS else None
        with storage.connect() as conn:
            conn.execute("UPDATE users SET failed_logins = ?, locked_until = ? WHERE id = ?",
                         (0 if locked else failed, locked, user["id"]))
        raise wrong

    with storage.connect() as conn:
        conn.execute("UPDATE users SET failed_logins = 0, locked_until = NULL WHERE id = ?", (user["id"],))
    if not user["verified"]:
        await issue_code(user)
        return JSONResponse(status_code=403, content={
            "code": "verification_required",
            "detail": "Check your email for a verification code to finish setting up your account.",
        })
    return {"token": start_session(user["id"]), "user": public_user(user)}


@router.post("/google")
async def google(body: GoogleToken):
    """Signs in with a Google ID token obtained by the app.

    Google has already verified the address, so no emailed code is needed — and
    that holds for township domains too, since a town on Google Workspace is
    vouching for its own mailboxes.
    """
    allowed = {c.strip() for c in os.environ.get("GOOGLE_CLIENT_IDS", "").split(",") if c.strip()}
    if not allowed:
        raise HTTPException(status_code=503, detail="Google sign-in is not configured on this server.")
    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get("https://oauth2.googleapis.com/tokeninfo", params={"id_token": body.id_token})
    if response.status_code != 200:
        raise HTTPException(status_code=401, detail="Google did not accept that sign-in.")
    claims = response.json()
    # `aud` must be one of our own client IDs, or a token minted for some other
    # app could be replayed here.
    if claims.get("aud") not in allowed or str(claims.get("email_verified")).lower() != "true":
        raise HTTPException(status_code=401, detail="Google did not accept that sign-in.")

    email = normalise(claims.get("email", ""))
    role, township = role_for(email, body.account_type)
    user = find_user(email)
    with storage.connect() as conn:
        if user is None:
            conn.execute(
                """INSERT INTO users (id, email, password_hash, role, township, verified, created_at)
                   VALUES (?, ?, NULL, ?, ?, 1, ?)""",
                (str(uuid.uuid4()), email, role, township, iso(utcnow())),
            )
        else:
            # A verified township sign-in upgrades the account; it is never downgraded here.
            new_role = "township" if role == "township" else user["role"]
            conn.execute("UPDATE users SET verified = 1, role = ?, township = ? WHERE id = ?",
                         (new_role, township or user["township"], user["id"]))
    user = find_user(email)
    return {"token": start_session(user["id"]), "user": public_user(user)}


@router.get("/me")
def me(user=Depends(require_user)):
    return public_user(user)


@router.post("/logout")
def logout(request: Request):
    token = bearer_token(request)
    if token:
        with storage.connect() as conn:
            conn.execute("DELETE FROM sessions WHERE token_hash = ?", (sha256(token),))
    return {"status": "signed_out"}
