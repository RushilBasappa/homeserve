# Runbook — alerting (ntfy + changedetection.io)

Two **Dell-only** stacks that together turn "something changed on the internet" into a
notification on your phone:

- **ntfy** — the generic push **sink**. Publishers POST to a topic; the ntfy phone app
  subscribes. Anything that can `curl` can publish, so every future alert source reuses it.
- **changedetection.io** — the first **publisher**. Polls a URL on a schedule and fires only
  when the watched content actually changes.

Upstream: <https://github.com/binwiederhier/ntfy> ·
<https://github.com/dgtlmoon/changedetection.io> · Operating the fleet: [[homeserve-ops-access]].

> **Driving use case:** US visa (H-4) appointment-slot alerts (see
> [The visa watch](#the-visa-watch-changedetection) below). Both stacks are general-purpose —
> the visa watch is just the first tenant.

> **Phase note:** `PLAN.md` Phase 9 (Alerting) plans **Uptime Kuma → ntfy**. This runbook lands
> the **ntfy half early**, driven by an unrelated need. Phase 9 still owns Uptime Kuma and the
> Beszel-threshold wiring — those publish into the ntfy deployed here rather than standing up a
> second sink.

---

## ⚠ Security posture — read first

The two stacks have **deliberately opposite** exposure, and it matters:

| | ntfy | changedetection |
|---|---|---|
| Traefik `ipAllowList` | **No** — reachable from any network | **Yes** — LAN + tailnet only |
| What guards it | `auth-default-access: deny-all` + no signup | Network position + a UI password |

**Why ntfy is not gated.** Since headscale made `:443` publicly router-forwarded, every Traefik
vhost is reachable from the internet by Host header. Most admin UIs answer that with an
`ipAllowList` (wud, headplane). ntfy must **not** be: the entire point is that alerts land on the
phone from a coffee shop, cell data, or abroad. Gating it to LAN/tailnet makes it useless exactly
when it matters. The **ACL is the trust boundary**, not the network — which is why the deny-all
default and the first-run user creation below are load-bearing, not optional hardening.

A stock ntfy is **wide open**: any caller may publish to or read any topic. Verify the lockdown
after deploy ([Audits](#audits-the-invariants)).

**Why changedetection *is* gated.** Its UI has no auth by default and will fetch any URL you type
— an unauthenticated request-forwarder is not something to leave answering on a public vhost.
More concretely, its datastore holds the **CheckVisaSlots API key** in the watch's request-headers
box, in the clear. So: network-gate it **and** set a UI password (Settings → General → password).
The **alerts** still escape to the phone from anywhere, because they leave via ntfy.

---

## Prerequisites

- Phase-3 edge live (Traefik + wildcard TLS + AdGuard); `ntfy.ragnaforge.xyz` and
  `changedetection.ragnaforge.xyz` resolve via the existing wildcard — **no new DNS records**.
- `komodo/stacks.toml` has both `[[stack]]` decls (server `ragnaforge-dell`); `RunSync` applied.
- **No Periphery secrets.** Neither compose references a `${VAR}`, so nothing is added to
  `komodo/bootstrap/periphery.compose.yaml` and **`make sync-secrets` is not needed**. Both
  `.mise.toml` values (`NTFY_VISA_TOKEN`, `CHECKVISASLOTS_API_KEY`) are consumed **by hand** at
  first-run config — same model as `PLEX_TOKEN` / `MEDIA_ADMIN_*`.
- Two small containers, no browser — see the compose header for why the browser sidecar was
  built, measured and removed.

**Verify at deploy** (image-tag discipline): confirm the pinned tags in both compose files are
current — `binwiederhier/ntfy:v2.26.3`, `dgtlmoon/changedetection.io:0.55.8`. Releases:
<https://github.com/binwiederhier/ntfy/releases> ·
<https://github.com/dgtlmoon/changedetection.io/releases>.

---

## Bring-up order

**ntfy first.** changedetection's notification URL needs an ntfy token that does not exist until
ntfy has run once.

### 1. Deploy ntfy

`DeployStack ntfy` in Komodo. One container. On first boot it creates an **empty** `user.db` — with
`deny-all` in force, that means *nothing can publish or subscribe yet*. That is expected.

### 2. Create the accounts (once, on the Dell)

```bash
# UI/CLI owner — the identity you log into the phone app and web UI with.
docker exec -it ntfy ntfy user add --role=admin admin

# Write-only publisher for changedetection. Least privilege: it can post to
# `visa` and do nothing else — it cannot read the topic back or touch any other.
docker exec -it ntfy ntfy user add visabot
docker exec -it ntfy ntfy access visabot visa wo

# Issue its token -> prints tk_...
docker exec -it ntfy ntfy token add visabot
```

Put that token in `.mise.toml` as `NTFY_VISA_TOKEN` (the placeholder is in
`.mise.toml.example`). It is kept there purely so there's one canonical place for it — no
tooling reads it.

Confirm the ACL:

```bash
docker exec ntfy ntfy access          # visabot -> visa: write-only; admin -> *
```

### 3. Subscribe the phone

Install the ntfy app, **Add server** → `https://ntfy.ragnaforge.xyz`, log in as `admin`,
subscribe to topic `visa`. Send a test:

```bash
docker exec ntfy ntfy publish visa "hello from the Dell"
```

**iPhone:** the compose sets `NTFY_UPSTREAM_BASE_URL: https://ntfy.sh`. Apple forbids the
background connection ntfy uses on Android, so iOS wake-ups must arrive via APNs through ntfy.sh.
What leaves the house is a **poll request containing a SHA-256 hash of the topic name and nothing
else** — no title, body, or priority; the phone then fetches the real message from your server.
**Android-only?** Comment that env line out and redeploy — nothing then touches ntfy.sh.

### 4. Deploy changedetection

`DeployStack changedetection` — one container.

⚠ **Check it reports `healthy`, not just `Up`:**

```bash
docker inspect changedetection --format '{{.State.Health.Status}}'
```

This is not a formality. The image ships **neither `wget` nor `curl`**, so a healthcheck
written the usual way fails forever, Docker marks the container `unhealthy`, and
**Traefik's Docker provider silently skips unhealthy containers** — the vhost then returns
Traefik's own `404 page not found` rather than a 502. That looks exactly like a DNS,
AdGuard or Cloudflare fault and is none of them. (It bit this stack on first deploy; the
compose now uses `python3` for the check.)

Then in the UI, Settings → General, **set a UI password** before creating any watch — see
the security posture above; the watch stores the CheckVisaSlots API key in the clear.

### 5. Create the visa watch

See the next section.

---

## The visa watch (changedetection)

**Target:** the JSON endpoint the CheckVisaSlots **browser extension** polls —
`https://app.checkvisaslots.com/slots/v3`, authenticated with the subscriber's own
`x-api-key`. Nothing here touches `ais.usvisa-info.com` with your own session cookie —
that's what every "visa bot" on GitHub does, and it's what gets accounts locked.

### Why not the public HTML page

The obvious target is `checkvisaslots.com/latest-us-visa-availability/h-4-regular/`.
It was tried first, thoroughly, and abandoned. Recorded so nobody repeats it:

- It sits behind **Vercel Attack Challenge Mode** — `HTTP 429` +
  `x-vercel-mitigated: challenge`, a JS proof-of-work interstitial. It **escalates**:
  once an IP is flagged it stays flagged for many hours, and a plain fetch with a real
  desktop User-Agent still gets challenged.
- A browser sidecar did **not** rescue it. Headless Chrome *and* headful-under-Xvfb both
  returned a stripped, unhydrated shell — 19 bytes of text — so the filter matched
  nothing and the watch silently never fired.
- ⚠ The checkpoint page embeds a **unique request ID per fetch** (`sfo1::1785830911-…`).
  Point a watch at it and *every* check registers as a change: a permanent false-alert
  generator.
- `app.checkvisaslots.com` is **not** challenge-gated — it answers `200` with clean JSON
  from the very same Dell IP the HTML page blocks. That's expected: the extension is
  itself a non-browser fetch client and can't solve a JS challenge either.

### Getting the API key

Open the extension popup → DevTools → **Network** → click the XHR → right-click →
**Copy as cURL**. The `x-api-key` header is the key; it's scoped to your subscription
(the response echoes `userDetails.visa_type`, so a different visa type means a different
key, not a different URL). Store it as `CHECKVISASLOTS_API_KEY` in `.mise.toml`.

### The watch

| Field | Value |
|---|---|
| **URL** | `https://app.checkvisaslots.com/slots/v3` |
| **Fetch method** | Basic fast Plaintext/HTTP Client — **not** a browser |
| **Request headers** | `x-api-key: <key>`, `origin: chrome-extension://beepaenfejnphdgnkmccjcfiieihhogl`, `extversion: 4.7.3`, a normal desktop `user-agent` |
| **Filter** | `jq:[.slotDetails[] \| select(.slots > 0) \| "\(.visa_location): \(.slots)"] \| if length == 0 then "none" else join(" \| ") end` |
| **Trigger → Trigger/wait for text** | `/: [1-9]/` |
| **Notification URL** | `ntfy://<NTFY_VISA_TOKEN>@ntfy/visa` |
| **Recheck time** | driven externally at **:00 / :30** — see [scheduling](#scheduling-on-the-half-hour) |

### Alert only on availability, never on a countdown

Two mechanisms stack, and both matter:

1. **The `select(.slots > 0)`** in the filter means the snapshot lists *only* locations that
   actually have slots. With nothing available it collapses to the literal `none`. The
   `if length == 0` guard is load-bearing — an empty filter result makes changedetection
   error with *"no filters were found"* instead of recording a clean empty state.
2. **`trigger_text` = `/: [1-9]/`** suppresses the notification unless the new snapshot
   contains a non-zero count. Without it you'd also get paged when a slot *disappears*
   (`CHENNAI VAC: 2` → `none`), which is noise.

Verified in both directions on deploy: all-zeros produced **no** notification, and a
snapshot of `"CHENNAI VAC: 3"` fired one. Note that with `trigger_text` set, changedetection
does not advance the stored snapshot on non-triggering checks either — so the diff in the
alert is against the last *triggering* state, which is what you want.

### Scheduling on the half hour

changedetection has **no cron**. `time_between_check` is a plain interval measured from
the *last* check, so the phase lands wherever the previous run finished and then drifts
by the fetch duration every cycle (~0.3 s per check — minutes per month).
`time_schedule_limit` is only a day/time **window** limiter ("only check 09:00–17:00");
it cannot pin checks to :00 and :30.

So alignment is driven from outside, by the **`changedetection-scheduler`** sidecar in
the stack: it sleeps to the next multiple of 1800 s, then pokes the recheck API for every
non-paused watch. It reads changedetection's own API token out of the datastore (mounted
read-only), so no secret enters git or the Periphery env, and it reuses the app image
rather than pulling a second one.

```bash
docker logs changedetection-scheduler     # "scheduler up; first recheck at 02:00:00"
```

⚠ **The watch's own interval is a FALLBACK only** — set to 6 h with
`time_between_check_use_default: false`. The sidecar refreshes `last_checked` every 30
min so that 6 h timer never elapses; it only takes over if the sidecar dies. **Do not
also set the watch to 30 min** — both would fire and double the quota burn.

⚠ **`time_between_check_use_default` is a trap.** It defaults to `true`, which makes the
**global** interval win and silently ignores the per-watch value. The global here is
**3 hours**, so a watch that reads "30 minutes" in its own config was really checking
every 3 h until the flag was cleared. Always verify the effective interval in
`/datastore/<uuid>/watch.json`, not just the form.

### ⚠ The endpoint is quota-metered

This drives the interval, not politeness. Every call decrements
`userActivity.remaining` by exactly 1 (measured: 412 → 411 → 410) and increments
`userActivity.slots`; the two sum to a fixed allowance. **The reset period is unknown**,
so the interval is deliberately conservative:

| Interval | Calls/day | Days from a full 437 allowance |
|---|---|---|
| 5 min | 288 | ~1.5 |
| 15 min | 96 | ~4.5 |
| **30 min** (current) | **48** | **~9** |
| 60 min | 24 | ~18 |

Your **own browser extension draws on the same allowance**, so real burn is higher than
this stack alone. Check the balance with a single call:

```bash
curl -s https://app.checkvisaslots.com/slots/v3 \
  -H "x-api-key: $CHECKVISASLOTS_API_KEY" \
  -H "origin: chrome-extension://beepaenfejnphdgnkmccjcfiieihhogl" | jq .userActivity
```

If `remaining` is falling faster than you like, lengthen the interval — that is the only
knob.

### Why that filter

The raw JSON is mostly churn: every `slotDetails` entry carries a `createdon` timestamp
and an `imghash` that change on each poll, and `userActivity.remaining` counts *down*
every call. Watch the raw body and it alerts every cycle forever while meaning nothing.
The jq expression reduces the response to one line of pure signal:

```
"CHENNAI VAC: 0 | HYDERABAD VAC: 0 | KOLKATA VAC: 0 | MUMBAI VAC: 0 | NEW DELHI VAC: 0"
```

so "the text changed" means "a slot count moved, or a location appeared/disappeared".

### Expectation-setting

By the time a slot surfaces on a third-party aggregator it is often already gone, and
CheckVisaSlots itself says the data is crowdsourced and "may not reflect real-time
openings". This gets you the alert; booking is still a manual race. Auto-booking against
the government site is where the real ToS and account-lockout risk lives, and is
deliberately not built here.

## Adding another publisher

ntfy is generic. To alert from anything else, mint a scoped user + token the same way:

```bash
docker exec -it ntfy ntfy user add <bot>
docker exec -it ntfy ntfy access <bot> <topic> wo
docker exec -it ntfy ntfy token add <bot>
```

Publish from any container on the `traefik` network:

```bash
curl -H "Authorization: Bearer tk_..." -d "disk 91% on the Dell" http://ntfy/<topic>
```

One topic per concern (`visa`, `uptime`, `disk`) so the phone can mute them independently.
Phase 9's Uptime Kuma and Beszel thresholds should land here rather than as a second sink.

---

## Audits (the invariants)

- **ntfy is genuinely closed.** From a machine **off** the LAN/tailnet:
  `curl -d test https://ntfy.ragnaforge.xyz/visa` → **403**, and
  `curl -s https://ntfy.ragnaforge.xyz/visa/json?poll=1` → **403**. A `200` on either means
  `deny-all` did not take — stop and fix before trusting it. Also confirm
  `curl -s https://ntfy.ragnaforge.xyz/v1/account` shows the anonymous user with no access.
- **No open signup:** `curl -d '{"username":"x","password":"y"}' https://ntfy.ragnaforge.xyz/v1/account`
  → rejected.
- **changedetection is not reachable off-net:** from off-LAN/off-VPN,
  `changedetection.ragnaforge.xyz` does not serve (Traefik `ipAllowList` → 403). On the LAN it
  prompts for the UI password.
- **No host ports:** `docker ps` on the Dell shows **no** published ports for any of the three
  containers; no router forward targets them.
- **The browser is unreachable except from changedetection:** `sockpuppetbrowser` has no Traefik
  labels and is not on the `traefik` network — `docker inspect -f '{{json .NetworkSettings.Networks}}' sockpuppetbrowser`
  should list **only** `changedetection_browser`. An unauthenticated headless browser on a routed
  network is a request-forwarder for anyone who reaches it.
- **No secrets in git:** `git grep -i "tk_"` returns only placeholders and prose. The ntfy token
  lives in `user.db`; the visa watch has no credential at all.
- **Golden rule:** `docker volume ls` on the Dell shows `ntfy_ntfy-data`, `ntfy_ntfy-cache`,
  `changedetection_changedetection-data`; **0** state on the Mac or under `/srv/nfs`.

---

## Troubleshooting

**Alerts stopped arriving on iPhone.** Almost always the `NTFY_UPSTREAM_BASE_URL` path. Confirm
it is still set, and that the phone's server entry is the full `https://ntfy.ragnaforge.xyz`.
Android has no such dependency.

**The watch diffs a "Vercel Security Checkpoint" page instead of the table.** The fetcher fell
back to plain HTTP. Either the watch is still set to the default requests fetcher (set it to
**Playwright/Sockpuppet Chrome**), or the sidecar is down — `docker logs sockpuppetbrowser`. A
crash loop on start is usually the missing `cap_add: SYS_ADMIN` or a too-small `shm_size`.

**changedetection alerts on every poll.** The filter isn't excluding the churn columns. The page's
"Relative Time" column (`58 mins ago`) re-renders every load. Open the watch's diff view — whatever
is highlighted is what still needs filtering; `td:nth-child(-n+5)` is the known-good selector.

**changedetection alerts never fire.** Check the notification URL resolves: from the container,
`docker exec changedetection wget -qO- http://ntfy/v1/health`. If that fails, the two stacks
aren't sharing the `traefik` network. If it succeeds but posts 403, the `visabot` token lacks
write access on that exact topic name.

**Checks got slow, or the Dell is swapping.** Each browser fetch is a full Chrome page load and
the watched page pulls in a pile of analytics/ad tags. Lower `FETCH_WORKERS`, lengthen the recheck
interval, or cap `MAX_CONCURRENT_CHROME_PROCESSES`. `docker stats sockpuppetbrowser` tells you
which.

**The page layout changed and the filter broke.** `td:nth-child(-n+5)` assumes the current
7-column table. If CheckVisaSlots reorders or adds columns, re-derive it: load the page in a real
browser and check which columns are churn before re-filtering.

**Editing ntfy env has no effect.** These are plain `environment:` values, not an inline
`configs:` block, so a normal `DeployStack` suffices — no `DestroyStack` recreate needed
(cf. [[homeserve-inline-configs-need-recreate]], which does *not* apply here).

---

## Backups gap (Phase 10)

Backrest is **not deployed yet** (`PLAN.md` Phase 10), so nothing here is backed up on a schedule.
When it lands, the volumes rank as:

| Volume | Value | Rebuild cost if lost |
|---|---|---|
| `ntfy_ntfy-data` | **Back up.** Accounts, ACLs, access tokens. | Re-run the `user add` / `access` / `token add` steps **and** re-paste the new token into every publisher. Annoying, not fatal. |
| `changedetection_changedetection-data` | **Back up.** Watches, filters, notification URLs, change history. | Rebuild every watch by hand — the URL, fetcher and CSS filter are recoverable from this runbook, the change history is not. |
| `ntfy_ntfy-cache` | **Skip.** Message cache + attachments, 24 h TTL. | Nothing; it's derived. |

**The honest gap:** changedetection has **no declarative config file** — watches live only in that
volume, so this pair is the least reproducible-from-git thing in the fleet
(cf. [[homeserve-portability-goal]]). The mitigation is that the full watch recipe is written down
in [The visa watch](#the-visa-watch-changedetection) above and in the compose header, so a
from-scratch rebuild is a 5-minute UI session rather than an archaeology project.
