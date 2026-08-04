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

**Why changedetection *is* gated.** Its UI has no auth by default, and it ships a **headless
browser that will fetch any URL you type** — an unauthenticated request-forwarder is not
something to leave answering on a public vhost. It also holds whatever credentials a future watch
needs in its request-headers box. So: network-gate it **and** set a UI password (Settings →
General → password). The **alerts** still escape to the phone from anywhere, because they leave
via ntfy.

The visa watch itself carries **no credential** — it reads a public page (see
[The visa watch](#the-visa-watch-changedetection)).

---

## Prerequisites

- Phase-3 edge live (Traefik + wildcard TLS + AdGuard); `ntfy.ragnaforge.xyz` and
  `changedetection.ragnaforge.xyz` resolve via the existing wildcard — **no new DNS records**.
- `komodo/stacks.toml` has both `[[stack]]` decls (server `ragnaforge-dell`); `RunSync` applied.
- **No Periphery secrets.** Neither compose references a `${VAR}`, so nothing is added to
  `komodo/bootstrap/periphery.compose.yaml` and **`make sync-secrets` is not needed**. The single
  `.mise.toml` value (`NTFY_VISA_TOKEN`) is consumed **by hand** at first-run config — same model
  as `PLEX_TOKEN` / `MEDIA_ADMIN_*`.
- **~2 GB RAM headroom on the Dell** for the `sockpuppetbrowser` sidecar (`shm_size: 2gb` plus the
  Chrome processes themselves). This is the heaviest thing either stack does.

**Verify at deploy** (image-tag discipline): confirm the pinned tags in both compose files are
current — `binwiederhier/ntfy:v2.26.3`, `dgtlmoon/changedetection.io:0.55.8`,
`dgtlmoon/sockpuppetbrowser:0.0.3`. Releases:
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

`DeployStack changedetection` — **two** containers come up, the app and the
`sockpuppetbrowser` headless-Chrome sidecar.

Confirm the sidecar is actually wired in, because a silent failure here just means every
browser-fetched watch quietly diffs a bot-challenge page:

```bash
docker logs sockpuppetbrowser | tail          # should show it listening, no crash loop
docker exec changedetection wget -qO- --spider ws://sockpuppetbrowser:3000 ; echo $?
```

Then in the UI, Settings → General:

1. **Set a UI password** — before creating any watch. See the security posture above.
2. Check the fetcher dropdown offers **Playwright/Sockpuppet Chrome**. If it doesn't,
   `PLAYWRIGHT_DRIVER_URL` didn't take and the visa watch will not work.

### 5. Create the visa watch

See the next section.

---

## The visa watch (changedetection)

**Target:** the **public** availability page —
<https://checkvisaslots.com/latest-us-visa-availability/h-4-regular/>

No account, no extension API key, no credential of any kind. And nothing here touches
`ais.usvisa-info.com` with your own session cookie — that's what every "visa bot" on GitHub does,
and it's what gets accounts rate-limited or locked.

### Why this needs a browser

A plain HTTP fetch of that URL returns, on the **first** request:

```
HTTP/2 429
server: Vercel
x-vercel-mitigated: challenge
<title>Vercel Security Checkpoint</title>
```

That's a **JS proof-of-work interstitial, not a rate limit** — backing off, spoofing a
User-Agent, or adding delays will never get past it. A headless Chromium solves it
automatically (verified). Hence the `sockpuppetbrowser` sidecar in the compose file, and hence
the fetcher setting below: leave it on the default requests fetcher and the watch will happily
diff the *challenge page* instead of the table.

There's no cleaner JSON endpoint to fall back on either. The table is server-rendered into the
Next.js RSC payload (so it's plain text in the DOM — good), and `/api/slot-booking/status/`
returns **401** for anonymous callers (logged-in booking only). Browser or nothing.

### The watch

| Field | Value |
|---|---|
| **URL** | `https://checkvisaslots.com/latest-us-visa-availability/h-4-regular/` |
| **Request → Fetch method** | **Playwright/Sockpuppet Chrome** — *not* the default |
| **Filters → CSS/XPath** | `td:nth-child(-n+5)` |
| **Trigger** | *Send notification when filter text changes* |
| **Notification URL** | `ntfy://<NTFY_VISA_TOKEN>@ntfy/visa` |
| **Recheck time** | 5 minutes |

### Why that filter

The page has exactly **one** table, with seven columns:

| # | Column | |
|---|---|---|
| 1 | Visa Location | keep |
| 2 | Visa Type | keep |
| 3 | Earliest Date | **keep — the thing you care about** |
| 4 | Slots on Earliest Date | **keep** |
| 5 | Total Dates Available | **keep** |
| 6 | Last Seen At | drop |
| 7 | Relative Time | drop — **churn** |

Column 7 (`58 mins ago`) re-renders on *every single load*, and the page footer stamps
"The current info is generated at &lt;now&gt;". Watch the raw page and it alerts every 5 minutes
forever while telling you nothing. `td:nth-child(-n+5)` keeps only columns 1–5, so "the text
changed" reduces to **"a location's earliest date or slot count actually moved."**

Dropping column 6 as well is deliberate: *Last Seen At* updates when the same availability is
merely re-confirmed, which isn't news. If you'd rather be pinged on re-confirmation too, widen
the filter to `td:nth-child(-n+6)`.

Two more things worth knowing:

- **The notification URL is container-to-container.** `ntfy` resolves over the shared `traefik`
  network, so the alert never leaves the Dell on its way out — no TLS hop, no public round trip,
  and it keeps working even if the edge is down.
- **5 minutes, not 30 seconds.** The page self-describes as refreshing every 2 minutes, and every
  check is a full headless Chrome page load (the site pulls in a pile of analytics/ad tags).
  Faster polling costs real RAM/CPU on a 7.5 GB node and buys at most ~3 minutes of latency.

### Watching a different visa type

The URL slug is the only thing that changes — `/latest-us-visa-availability/<type>/`, e.g.
`h-1b-regular`, `b1-b2-regular`, `f1-regular`. Clone the watch, swap the slug, and send it to its
own ntfy topic if you want to mute them independently.

### Expectation-setting

By the time a slot surfaces on a third-party aggregator, it is often already gone — and the page
itself says the data is crowdsourced, "may not reflect real-time openings and is for reference
only." This gets you the alert; booking is still a manual race. Full auto-booking against the
government site is where the real ToS and account-lockout risk lives, and is deliberately not
built here.

---

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
