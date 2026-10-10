"""End-to-end checks for accounts, township verification and hazard removal.

Runs against a live server with a throwaway database. Verification codes are read
from the server log, which is where they go when no email provider is configured.

    cd backend
    STORMWATCH_DB=/tmp/check.db .venv/bin/uvicorn main:app --port 8014 --log-level warning > /tmp/check.log 2>&1 &
    .venv/bin/python tests/check_accounts.py /tmp/check.log

Every address used here is on example.com or is never emailed: with no
RESEND_API_KEY set, nothing leaves the machine.
"""
import re, secrets, sys, httpx
B = "http://127.0.0.1:8014"; LOG = sys.argv[1]
c = httpx.Client(base_url=B, timeout=10)
ok = fail = 0
def check(name, cond, extra=""):
    global ok, fail
    if cond: ok += 1; print("  pass ", name)
    else: fail += 1; print("  FAIL ", name, extra)
def code_for(email):
    hits = re.findall(rf"verification code for {re.escape(email)} is (\d{{6}})", open(LOG).read())
    return hits[-1]
def account(email, kind="resident"):
    pw = secrets.token_urlsafe(12)
    r = c.post("/api/v1/auth/signup", json={"email": email, "password": pw, "account_type": kind})
    assert r.status_code == 200, r.text
    r = c.post("/api/v1/auth/verify", json={"email": email, "code": code_for(email)})
    assert r.status_code == 200, r.text
    return {"Authorization": "Bearer " + r.json()["token"]}, pw, r.json()["user"]

print("-- sign-up and verification")
pw = secrets.token_urlsafe(12)
r = c.post("/api/v1/auth/signup", json={"email": "Ana@Example.com", "password": pw})
check("signup asks for verification", r.status_code == 200 and r.json()["status"] == "verification_required")
check("code is not in the response", not re.search(r"\d{6}", r.text))
r = c.post("/api/v1/auth/login", json={"email": "ana@example.com", "password": pw})
check("login blocked until verified", r.status_code == 403 and r.json()["code"] == "verification_required")
r = c.post("/api/v1/auth/verify", json={"email": "ana@example.com", "code": "000000" if code_for("ana@example.com") != "000000" else "111111"})
check("wrong code rejected", r.status_code == 400)
r = c.post("/api/v1/auth/verify", json={"email": "ana@example.com", "code": code_for("ana@example.com")})
check("right code signs in", r.status_code == 200 and r.json()["user"]["role"] == "resident")
ana = {"Authorization": "Bearer " + r.json()["token"]}
check("code cannot be reused", c.post("/api/v1/auth/verify", json={"email": "ana@example.com", "code": code_for("ana@example.com")}).status_code == 400)
check("login works after verify", c.post("/api/v1/auth/login", json={"email": "ana@example.com", "password": pw}).status_code == 200)
check("wrong password rejected", c.post("/api/v1/auth/login", json={"email": "ana@example.com", "password": "x" * 12}).status_code == 401)
check("unknown email gives same error", c.post("/api/v1/auth/login", json={"email": "nobody@example.com", "password": "x" * 12}).status_code == 401)
check("duplicate signup refused", c.post("/api/v1/auth/signup", json={"email": "ana@example.com", "password": pw}).status_code == 409)
check("short password refused", c.post("/api/v1/auth/signup", json={"email": "b@example.com", "password": "short"}).status_code == 400)
check("/me with token", c.get("/api/v1/auth/me", headers=ana).json()["email"] == "ana@example.com")
check("/me without token is 401", c.get("/api/v1/auth/me").status_code == 401)
check("/me with junk token is 401", c.get("/api/v1/auth/me", headers={"Authorization": "Bearer junk"}).status_code == 401)

print("-- brute-force limits")
c.post("/api/v1/auth/signup", json={"email": "lock@example.com", "password": secrets.token_urlsafe(12)})
real = code_for("lock@example.com")
for _ in range(5): c.post("/api/v1/auth/verify", json={"email": "lock@example.com", "code": "999999" if real != "999999" else "888888"})
check("code dies after 5 wrong guesses", c.post("/api/v1/auth/verify", json={"email": "lock@example.com", "code": real}).status_code == 400)
for _ in range(5): c.post("/api/v1/auth/login", json={"email": "ana@example.com", "password": "y" * 12})
check("account locks after 5 bad passwords", c.post("/api/v1/auth/login", json={"email": "ana@example.com", "password": pw}).status_code == 429)

print("-- township accounts")
def twp(email): return c.post("/api/v1/auth/signup", json={"email": email, "password": secrets.token_urlsafe(12), "account_type": "township"})
check("gmail refused as township", twp("mayor@gmail.com").status_code == 400)
check("suffix trick refused", twp("a@princetonnj.gov.example.com").status_code == 400)
check("lookalike prefix refused", twp("a@notprincetonnj.gov").status_code == 400)
check("subdomain refused", twp("a@mail.princetonnj.gov").status_code == 400)
check("two @ signs refused", twp("a@princetonnj.gov@example.com").status_code == 400)
r = twp("Clerk@PlainsboroNJ.com")
check("real domain accepted, any case", r.status_code == 200)
r = c.post("/api/v1/auth/login", json={"email": "clerk@plainsboronj.com", "password": "whatever-123"})
check("township unusable before verification", r.status_code in (401, 403))
town, _, town_user = account("dpw@princetonnj.gov", "township")
check("verified township has role + town", town_user["role"] == "township" and town_user["township"] == "Princeton")
check("domain list served", len(c.get("/api/v1/auth/township-domains").json()) == 19)

print("-- hazards: ownership and the 3-vote rule")
def post(headers, lat, code="DOWNED_TREE"):
    r = c.post("/georeport/v2/requests.json", data={"service_code": code, "lat": lat, "long": -74.5893}, headers=headers)
    return r.json()[0]["service_request_id"]
bo, _, _ = account("bo@example.com"); cy, _, _ = account("cy@example.com"); di, _, _ = account("di@example.com"); ed, _, _ = account("ed@example.com")
h = post(bo, 40.33)
mine = [x for x in c.get("/api/v1/hazards", headers=bo).json() if x["id"] == h][0]
theirs = [x for x in c.get("/api/v1/hazards", headers=cy).json() if x["id"] == h][0]
check("reporter sees is_mine", mine["is_mine"] and not theirs["is_mine"])
check("owner id never exposed", "owner_id" not in mine and "bo@example.com" not in c.get("/api/v1/hazards").text)
check("vote needs sign-in", c.post(f"/api/v1/hazards/{h}/not-there").status_code == 401)
check("reporter cannot vote own", c.post(f"/api/v1/hazards/{h}/not-there", headers=bo).status_code == 400)
check("stranger cannot delete", c.delete(f"/api/v1/hazards/{h}", headers=cy).status_code == 403)
r1 = c.post(f"/api/v1/hazards/{h}/not-there", headers=cy).json()
r1b = c.post(f"/api/v1/hazards/{h}/not-there", headers=cy).json()
check("same person voting twice counts once", r1["not_there_votes"] == 1 and r1b["not_there_votes"] == 1 and not r1b["removed"])
r2 = c.post(f"/api/v1/hazards/{h}/not-there", headers=di).json()
check("2 votes: still there", r2["not_there_votes"] == 2 and not r2["removed"] and c.get(f"/georeport/v2/requests/{h}.json").status_code == 200)
seen = [x for x in c.get("/api/v1/hazards", headers=di).json() if x["id"] == h][0]
check("list shows count and my vote", seen["not_there_votes"] == 2 and seen["i_voted_not_there"])
r3 = c.post(f"/api/v1/hazards/{h}/not-there", headers=ed).json()
check("3rd distinct vote removes it", r3["removed"])
check("gone from Open311", c.get(f"/georeport/v2/requests/{h}.json").status_code == 404)
check("gone from GeoJSON feed", h not in c.get("/api/v1/hazards/feed.geojson").text)
check("gone from app list", h not in c.get("/api/v1/hazards").text)
check("voting on removed hazard is 404", c.post(f"/api/v1/hazards/{h}/not-there", headers=ed).status_code == 404)

h2 = post(bo, 40.35)
check("reporter can remove own", c.delete(f"/api/v1/hazards/{h2}", headers=bo).status_code == 200 and h2 not in c.get("/api/v1/hazards").text)
h3 = post(bo, 40.37)
check("resident cannot set crew status", c.patch(f"/api/v1/hazards/{h3}/status", json={"status": "IN_PROGRESS"}, headers=cy).status_code == 403)
check("township can set crew status", c.patch(f"/api/v1/hazards/{h3}/status", json={"status": "IN_PROGRESS"}, headers=town).json()["status"] == "IN_PROGRESS")
check("township can remove any", c.delete(f"/api/v1/hazards/{h3}", headers=town).status_code == 200)
h4 = post({}, 40.39)
check("anonymous report has no owner", not [x for x in c.get("/api/v1/hazards", headers=bo).json() if x["id"] == h4][0]["is_mine"])
check("logout kills the token", c.post("/api/v1/auth/logout", headers=bo).status_code == 200 and c.get("/api/v1/auth/me", headers=bo).status_code == 401)
check("google refused when unconfigured", c.post("/api/v1/auth/google", json={"id_token": "x"}).status_code == 503)
print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
