# Watch the library on your TV

Two one-time steps: **join the VPN**, then **install a media app**. After that it just works, on or off Wi‑Fi.

## What I'll send you

A WireGuard config file named something like `friend.conf`. Keep it private — it's your key into the network.

## Step 1 — Join the VPN (WireGuard)

1. On your TV, install the **WireGuard** app from the app store (Fire TV, Android TV, and Google TV all have it).
2. Get the `friend.conf` file onto the TV:
   - **Fire TV:** use the *Send Files to TV* app (or a USB stick) to copy `friend.conf` over.
   - **Android/Google TV:** copy it via USB or a file-share app.
3. Open WireGuard → **Import tunnel from file** → pick `friend.conf`.
4. Toggle the tunnel **on**. That's it — your TV is now on the network.

> This is a split tunnel: only my server traffic goes through it. Your normal streaming, browsing, and speed are unaffected, and you can leave it on all the time.

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

- Make sure the **WireGuard tunnel is toggled on** (Step 1.4) — nothing works without it.
- Fully close and reopen the media app after turning the tunnel on.
- Still stuck? Send me a screenshot and I'll check from my end.
