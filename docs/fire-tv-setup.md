# Watch the library on your TV

Two one-time steps: **join the VPN**, then **install a media app**. After that it just works, on or off Wi‑Fi.

## What I'll send you

A WireGuard config file named something like `vpn.conf`. Keep it private — it's your key into the network.

## Step 1 — Join the VPN (WireGuard) — Fire TV / Fire Stick only

1. Install the **Downloader** app. Allow it to install apps when asked.
2. In Downloader, paste this link and install it:
   ```
   https://github.com/wgtunnel/android/releases/download/5.1.0/wgtunnel-standalone-v5.1.0.apk
   ```
3. Put `vpn.conf` in a **gist** at gist.github.com (the gist filename must match the config filename), click **Raw**, copy the link. The URL should end with `<filename>.conf`.
4. Open **WG Tunnel** → **Add from URL** → paste the link → save.
5. Toggle the tunnel **on**.
6. **Delete the gist.**

> ⚠️ Keep the gist up **only** until WG Tunnel loads it (step 4), then **delete it**. The file is your private key — never leave it at a public URL.

> This is a split tunnel: only my server traffic goes through it. Your normal streaming and speed are unaffected, and you can leave it on all the time.

## Step 2 — Install a media app and sign in

### Jellyfin (recommended — free, no account needed)

1. Install **Jellyfin** from your TV's app store.
2. When it asks for a **server address**, enter:
   ```
   https://jellyfin.ragnaforge.xyz
   ```
3. Sign in with the username/password I give you.

### Plex (alternative)

1. Install **Plex** from your TV's app store.
2. Sign in with the Plex account I invite (I'll send the invite to your email).
3. My server + shared library appear automatically once the VPN is on.

## If it doesn't connect

- Make sure the **tunnel is toggled on in WG Tunnel** (Step 5) — nothing works without it.
- Fully close and reopen the media app after turning the tunnel on.
- Still stuck? Send me a screenshot and I'll check from my end.
