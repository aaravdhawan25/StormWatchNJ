"""Live checks against the deployed Supabase backend.

Needs two confirmed resident accounts that share a password. Create them in the
Supabase dashboard (Authentication > Users > Add user, with "Auto Confirm User"
on) so no email is sent, then:

    SW_REPORTER=a@example.com SW_VOTER=b@example.com SW_PASSWORD=... python3 supabase/tests/check_live.py

It files one hazard and removes it again. Delete the two accounts afterwards.
"""
import json, os, sys, urllib.request, urllib.parse, urllib.error
REPORTER, VOTER, PASSWORD = os.environ["SW_REPORTER"], os.environ["SW_VOTER"], os.environ["SW_PASSWORD"]
U = "https://yvmmtuqwjvztvxwpmfwf.supabase.co"; K = "sb_publishable_J48JNj6IRTzpzwkBsgM_MQ_NmERLY1v"
ok = bad = 0
def call(method, path, token=None, body=None, form=None, key=True):
    h = {}
    if key: h["apikey"] = K
    if token: h["Authorization"] = "Bearer " + token
    data = None
    if body is not None: data = json.dumps(body).encode(); h["Content-Type"] = "application/json"
    if form is not None: data = urllib.parse.urlencode(form).encode(); h["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(U + path, data=data, headers=h, method=method)
    try:
        r = urllib.request.urlopen(req, timeout=30); raw = r.read(); status = r.status; ct = r.headers.get("Content-Type", "")
    except urllib.error.HTTPError as e:
        raw = e.read(); status = e.code; ct = e.headers.get("Content-Type", "")
    try: parsed = json.loads(raw) if raw else None
    except Exception: parsed = raw.decode(errors="replace")[:200]
    return status, parsed, ct
def check(name, cond, extra=""):
    global ok, bad
    if cond: ok += 1; print("  pass ", name)
    else: bad += 1; print("  FAIL ", name, extra)
def login(email):
    s, d, _ = call("POST", "/auth/v1/token?grant_type=password", body={"email": email, "password": PASSWORD})
    assert s == 200, (s, d); return d["access_token"], d
print("-- sign-in"); rep, sess = login(REPORTER); vot, _ = login(VOTER)
check("password sign-in returns session", "refresh_token" in sess and sess["user"]["email"] == REPORTER.lower())
s, d, _ = call("POST", "/auth/v1/token?grant_type=refresh_token", body={"refresh_token": sess["refresh_token"]})
check("refresh token works", s == 200 and "access_token" in d, (s, d)); rep = d["access_token"]
s, d, _ = call("GET", "/rest/v1/profiles?select=role,township", token=rep)
check("own profile readable, role resident", s == 200 and d == [{"role": "resident", "township": None}], (s, d))
s, d, _ = call("GET", "/rest/v1/profiles?select=id")
check("anon reads no profiles", s == 200 and d == [], (s, d))
s, d, _ = call("GET", "/rest/v1/township_domains?select=domain,name&order=name")
check("19 township domains public", s == 200 and len(d) == 19, (s, d))
s, d, _ = call("POST", "/rest/v1/rpc/township_for_email", body={"p_email": "a@notprincetonnj.gov"})
check("lookalike domain not a township", s == 200 and d is None, (s, d))
s, d, _ = call("POST", "/rest/v1/rpc/township_for_email", body={"p_email": "Clerk@PrincetonNJ.gov"})
check("real domain recognised", d == "Princeton", (s, d))

print("-- locked-down tables and functions")
for t in ["hazards", "hazard_votes", "removed_hazards", "dispatch_towns"]:
    s, d, _ = call("GET", f"/rest/v1/{t}?select=*", token=rep)
    check(f"signed-in user cannot read {t} directly", s in (401, 403) or d == [], (s, d))
s, d, _ = call("POST", "/rest/v1/hazards", token=rep, body={"report_type": "OTHER", "severity": "LOW", "road_status": "CLEAR_TO_PASS", "description": "x", "latitude": 40.3, "longitude": -74.5})
check("cannot insert hazards directly", s in (401, 403), (s, d))
s, d, _ = call("PATCH", "/rest/v1/profiles?id=not.is.null", token=rep, body={"role": "township"})
check("cannot promote self to township", s in (401, 403) or d in ([], None), (s, d))
s, d, _ = call("GET", "/rest/v1/profiles?select=role", token=rep); check("still resident after attempt", d == [{"role": "resident"}], d)
s, d, _ = call("POST", "/rest/v1/rpc/list_hazards", body={}); check("anon cannot list hazards", s in (401, 403, 404), (s, d))
s, d, _ = call("POST", "/rest/v1/rpc/archive_and_delete_hazard", token=rep, body={"p_hazard": "00000000-0000-0000-0000-000000000000", "p_reason": "township", "p_by": None})
check("internal delete helper not callable", s in (401, 403, 404), (s, d))

print("-- Open311")
G = "/functions/v1/georeport"
s, d, _ = call("GET", G + "/services.json", key=False); check("services public, 5 codes", s == 200 and len(d) == 5, (s, d))
s, d, _ = call("GET", G + "/services/DOWNED_WIRE.json", key=False); check("service definition", s == 200 and len(d["attributes"]) == 5, (s, d))
s, d, _ = call("GET", G + "/discovery.json", key=False); check("discovery", s == 200 and d["endpoints"][0]["url"].endswith("/georeport"), (s, d))
F = {"service_code": "DOWNED_TREE", "lat": "40.3318", "long": "-74.5893", "address_string": "12 Dey Rd, Plainsboro, NJ 08536",
     "description": "Oak across both lanes & wires + more = bad", "attribute[severity]": "IMPASSABLE", "attribute[road_status]": "IMPASSABLE",
     "attribute[utility_lines_involved]": "true", "attribute[municipality]": "Plainsboro", "email": "someone@example.com", "phone": "5551234567"}
s, d, _ = call("POST", G + "/requests.json", form=F, key=False); check("anonymous POST refused", s == 403, (s, d))
s, d, _ = call("POST", G + "/requests.json", form=F, token=K); check("publishable key alone refused", s == 403, (s, d))
s, d, _ = call("POST", G + "/requests.json", form=dict(F, api_key="guess"), key=False); check("wrong api_key refused", s == 403, (s, d))
s, d, _ = call("POST", G + "/requests.json", form=F, token=rep); check("signed-in POST creates", s == 201 and "Received" in d[0]["service_notice"], (s, d)); hid = d[0]["service_request_id"]
s, d, _ = call("POST", G + "/requests.json", form=dict(F, lat="40.33185", long="-74.58935"), token=vot)
check("same spot becomes confirmation", s == 201 and d[0]["service_request_id"] == hid and "confirmation" in d[0]["service_notice"], (s, d))
s, d, _ = call("POST", G + "/requests.json", form={"lat": "40.3", "long": "-74.5"}, token=rep); check("missing service_code 400", s == 400, (s, d))
s, d, _ = call("POST", G + "/requests.json", form={"service_code": "POTHOLE", "lat": "40.3", "long": "-74.5"}, token=rep); check("unknown service 404", s == 404, (s, d))
s, d, _ = call("POST", G + "/requests.json", form={"service_code": "OTHER", "lat": "37.33", "long": "-122.0"}, token=rep); check("outside NJ 400", s == 400 and "New Jersey" in d[0]["description"], (s, d))
s, d, _ = call("POST", G + "/requests.json", form={"service_code": "OTHER", "address_string": "Main St"}, token=rep); check("address only 400", s == 400, (s, d))
s, d, _ = call("GET", G + f"/requests/{hid}.json", key=False)
check("GET one: 17 fields, zip parsed, special chars intact", s == 200 and len(d[0]) == 17 and d[0]["zipcode"] == "08536" and d[0]["description"] == F["description"], (s, d))
s, d, _ = call("GET", G + "/requests.json?status=open&service_code=DOWNED_TREE", key=False); check("GET list filtered", s == 200 and [x["service_request_id"] for x in d] == [hid], (s, d))
s, d, _ = call("GET", G + "/requests.json?status=nope", key=False); check("bad status 400", s == 400, (s, d))

print("-- feed")
s, d, ct = call("GET", "/functions/v1/hazard-feed", key=False)
check("GeoJSON feed public", s == 200 and "geo+json" in ct and d["type"] == "FeatureCollection" and len(d["features"]) == 1, (s, ct))
f = d["features"][0]; check("lon-first, 2 confirmations", f["geometry"]["coordinates"] == [-74.5893, 40.3318] and f["properties"]["confirmations"] == 2, f)
blob = json.dumps(d); check("no reporter data in feed", "someone@example.com" not in blob and "5551234567" not in blob and "owner" not in blob and REPORTER.lower() not in blob)

print("-- app calls")
s, d, _ = call("POST", "/rest/v1/rpc/list_hazards", token=rep, body={}); mine = [x for x in d if x["id"] == hid][0]
check("reporter sees is_mine, no owner field", mine["is_mine"] and "owner_id" not in mine, mine)
s, d, _ = call("POST", "/rest/v1/rpc/list_hazards", token=vot, body={}); check("voter does not see is_mine", not [x for x in d if x["id"] == hid][0]["is_mine"])
s, d, _ = call("POST", "/rest/v1/rpc/vote_not_there", token=rep, body={"p_hazard": hid}); check("reporter cannot vote own", s == 400 and "remove it" in d["message"], (s, d))
s, d, _ = call("POST", "/rest/v1/rpc/vote_not_there", token=vot, body={"p_hazard": hid}); check("vote counts 1 of 3", s == 200 and d == {"removed": False, "not_there_votes": 1, "not_there_threshold": 3}, (s, d))
s, d, _ = call("POST", "/rest/v1/rpc/remove_hazard", token=vot, body={"p_hazard": hid}); check("voter cannot remove", s in (401, 403) and "Only the person" in d["message"], (s, d))
s, d, _ = call("POST", "/rest/v1/rpc/set_hazard_status", token=vot, body={"p_hazard": hid, "p_status": "RESOLVED"}); check("resident cannot set status", s in (401, 403), (s, d))
s, d, _ = call("POST", "/rest/v1/rpc/remove_hazard", token=rep, body={"p_hazard": hid}); check("reporter removes own", s == 200 and d == {"removed": True}, (s, d))
s, d, _ = call("GET", G + f"/requests/{hid}.json", key=False); check("gone from Open311", s == 404, (s, d))
s, d, _ = call("POST", "/rest/v1/rpc/vote_not_there", token=vot, body={"p_hazard": hid}); check("vote on removed hazard says so", s >= 400 and "no longer" in d["message"], (s, d))

print("-- analyze-image")
s, d, _ = call("POST", "/functions/v1/analyze-image", key=False); check("no token refused", s == 401, (s, d))
s, d, _ = call("POST", "/functions/v1/analyze-image", token=rep, form={"x": "y"}); check("signed in, no Gemini key: 503", s == 503, (s, d))
s, d, _ = call("POST", "/auth/v1/logout", token=vot); check("logout", s == 204, (s, d))
print(f"\n{ok} passed, {bad} failed")
sys.exit(1 if bad else 0)
