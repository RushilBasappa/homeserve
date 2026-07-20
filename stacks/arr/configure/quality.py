#!/usr/bin/env python3
"""stacks/arr/configure/quality.py — PLANE 3 (application config), co-located with the
arr stack, run POST-DEPLOY, idempotently.

Implements the operator's "small 4K, else 1080p" policy (YTS-style efficiency, not
TRaSH's quality-maximising defaults):

  * Size caps on 2160p (quality definitions, MB/min — these scale with runtime):
      - Radarr (movies):  max ~125 MB/min  → ~15 GB for a 2 h movie
      - Sonarr (series):  max ~100 MB/min  → ~5 GB for a ~50 min episode
    Anything bigger (remuxes, 20 GB encodes) is rejected.
  * A "UHD + 1080p (efficient)" quality profile that ALLOWS WEB/Bluray 2160p (the
    small-4K sources) and WEB/Bluray 1080p (fallback), but NOT Remux-2160p. So the
    PVR grabs small 4K when it exists and drops to 1080p when it doesn't — for free.
  * Points Seerr's Radarr/Sonarr fulfilment at this profile.

Idempotent: re-running only changes what drifted. API keys + PLEX_TOKEN from mise.
RUN:  cd stacks/arr/configure && mise exec -- python3 quality.py
"""
import os
import json
import sys
import urllib.request
import urllib.error

PROFILE_NAME = "UHD + 1080p (efficient)"
# Qualities the profile allows (small-4K sources + 1080p fallback; NO 2160p remux).
ALLOW = {
    "WEBDL-2160p", "WEBRip-2160p", "Bluray-2160p",
    "WEBDL-1080p", "WEBRip-1080p", "Bluray-1080p",
}
CUTOFF_QUALITY = "Bluray-2160p"   # stop upgrading once we have a (size-capped) 4K Bluray


def api(base, path, key, method="GET", body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        base + path, data=data, method=method,
        headers={"X-Api-Key": key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        print(f"    ! {method} {path} -> {e.code}: {e.read()[:200].decode(errors='replace')}")
        raise


def cap_2160p(base, key, max_mbmin, pref_mbmin):
    defs = api(base, "/api/v3/qualitydefinition", key)
    changed = False
    for d in defs:
        if "2160" in d["quality"]["name"]:
            if d.get("maxSize") != max_mbmin or (d.get("preferredSize") or 0) > max_mbmin:
                d["maxSize"] = max_mbmin
                d["preferredSize"] = pref_mbmin
                changed = True
    if changed:
        api(base, "/api/v3/qualitydefinition/update", key, "PUT", defs)
    return changed


def ensure_profile(base, key):
    profs = api(base, "/api/v3/qualityprofile", key)
    existing = next((p for p in profs if p["name"] == PROFILE_NAME), None)
    if existing:
        return existing["id"], False
    schema = api(base, "/api/v3/qualityprofile/schema", key)
    cutoff_id = None

    def apply(item):
        nonlocal cutoff_id
        subs = item.get("items") or []
        if subs:  # a group (e.g. "WEB 2160p")
            any_allowed = False
            for s in subs:
                nm = s["quality"]["name"]
                s["allowed"] = nm in ALLOW
                any_allowed = any_allowed or s["allowed"]
                if nm == CUTOFF_QUALITY:
                    cutoff_id = s["quality"]["id"]
            item["allowed"] = any_allowed
        else:
            q = item.get("quality", {})
            item["allowed"] = q.get("name") in ALLOW
            if q.get("name") == CUTOFF_QUALITY:
                cutoff_id = q.get("id")

    for it in schema["items"]:
        apply(it)
    schema["name"] = PROFILE_NAME
    schema["upgradeAllowed"] = True
    schema["cutoff"] = cutoff_id
    api(base, "/api/v3/qualityprofile", key, "POST", schema)
    new = next(p for p in api(base, "/api/v3/qualityprofile", key)
               if p["name"] == PROFILE_NAME)
    return new["id"], True


def point_seerr(kind, profile_id):
    """kind = 'radarr' or 'sonarr'. Update Seerr's server to use the new profile."""
    seerr = "https://seerr.ragnaforge.xyz"
    token = os.environ["PLEX_TOKEN"]
    # authenticate (owner via Plex) → session cookie
    data = json.dumps({"authToken": token}).encode()
    cj = urllib.request.HTTPCookieProcessor()
    opener = urllib.request.build_opener(cj)
    req = urllib.request.Request(seerr + "/api/v1/auth/plex", data=data,
                                 headers={"Content-Type": "application/json"})
    opener.open(req, timeout=40).read()
    servers = json.loads(opener.open(seerr + f"/api/v1/settings/{kind}", timeout=40).read())
    changed = False
    for s in servers:
        if s.get("activeProfileId") == profile_id:
            continue
        sid = s["id"]
        body_obj = {k: v for k, v in s.items() if k != "id"}  # id is read-only (in the URL)
        body_obj["activeProfileId"] = profile_id
        put = urllib.request.Request(seerr + f"/api/v1/settings/{kind}/{sid}",
                                     data=json.dumps(body_obj).encode(), method="PUT",
                                     headers={"Content-Type": "application/json"})
        opener.open(put, timeout=40).read()
        changed = True
    return changed


def main():
    R = os.environ["RADARR_API_KEY"]
    S = os.environ["SONARR_API_KEY"]
    radarr, sonarr = "https://radarr.ragnaforge.xyz", "https://sonarr.ragnaforge.xyz"

    print("Radarr (movies):")
    print("  size cap 2160p ->", "updated" if cap_2160p(radarr, R, 125, 110) else "already set",
          "(max 125 MB/min ~= 15 GB / 2 h)")
    rid, created = ensure_profile(radarr, R)
    print(f"  profile '{PROFILE_NAME}' id={rid} ({'created' if created else 'exists'})")

    print("Sonarr (series):")
    print("  size cap 2160p ->", "updated" if cap_2160p(sonarr, S, 100, 90) else "already set",
          "(max 100 MB/min ~= 5 GB / 50 min)")
    sid, created = ensure_profile(sonarr, S)
    print(f"  profile '{PROFILE_NAME}' id={sid} ({'created' if created else 'exists'})")

    print("Seerr fulfilment default profile:")
    print("  radarr ->", "updated" if point_seerr("radarr", rid) else "already set")
    print("  sonarr ->", "updated" if point_seerr("sonarr", sid) else "already set")
    print("Done. New requests grab size-capped 4K when available, else 1080p.")


if __name__ == "__main__":
    sys.exit(main())
