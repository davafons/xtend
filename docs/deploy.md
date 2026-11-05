# Deploying to the server

Nothing has been deployed yet. This page lists what a deployment needs. The owner approves the host details before anything is exposed.

## What the app expects

| Setting | Purpose |
| --- | --- |
| `APP_HOSTS` | Comma-separated public hostnames, such as `crm.example.com`. The server won't boot without it, and other `Host` headers get 403. |
| `SECRET_KEY_BASE` | Signs sessions and hashes connector tokens. Generate it with `openssl rand -hex 64` and keep it stable: changing it signs everyone out and invalidates connector tokens. |
| `/data` volume | Holds `production.sqlite3` and `x-token.key`, which encrypts saved X tokens. Back up both together. A database backup without the key can't decrypt X tokens. |
| TLS in front | The app assumes HTTPS (`assume_ssl`, `force_ssl`, secure cookies, HSTS). Cloudflare Tunnel terminates TLS and forwards to port 3000. |
| X developer app | Each workspace saves its own X app in Data & settings. Its callback must be `https://<host>/x/connection/callback`. Owned-rate pricing only applies to the owner's own app. |

## Build and run on the server

the server is reached through a Cloudflare Tunnel, so no port is published on the host. `compose.yaml` runs the app and `cloudflared` side by side.

1. In Cloudflare Zero Trust, create a tunnel and copy its token. Add a public hostname, such as `crm.example.com`, that routes to `http://web:3000`.
2. On the server, create a `.env` next to `compose.yaml` holding `APP_HOSTS=crm.example.com`, `SECRET_KEY_BASE=<openssl rand -hex 64>`, and `TUNNEL_TOKEN=<token>`. Never commit it.
3. Build and start:

```sh
docker build --build-context lostcoords-ui=../lostcoords-ui -t twitter-crm .
docker compose up -d
docker compose exec web ./bin/rails users:create EMAIL=you@example.com
```

`users:create` asks for the password without echoing it. `users:password EMAIL=...` changes a password and signs out that user's sessions. There is no signup page.

Cloudflare terminates TLS. `cloudflared` reaches the app from a private Docker address, and Rails trusts private proxies, so `X-Forwarded-For` gives the visitor's IP and rate limits count each visitor separately. `test/integration/proxy_test.rb` covers this. Because no host port is published, nobody can bypass the tunnel and fake that header.

Optional extra layer: a Cloudflare Access policy on every path except `/mcp` and `/up` adds a second login in front of the app. Grok Bot can't pass Access, so `/mcp` has to stay outside the policy.

The `lostcoords-ui` gem is pinned to commit `19ef2a7` of the sibling checkout, which isn't on GitHub. The build copies that checkout's git history in as a named build context, so either build on a machine that has the sibling checkout, or push or tag that commit on `lostcoords/ui` and point the Gemfile at GitHub.

## What is public

- Every page requires a signed-in session, except `/session/new` and `/up`.
- `/mcp` is authenticated by the workspace's connector token, not by a session. Grok Bot uses `https://<host>/mcp` with that token.
- Sign-in allows 10 attempts per 3 minutes per IP. `/mcp` allows 120 requests per minute per IP.
- The Content Security Policy only allows scripts from the app's own origin.

## Before exposing it

1. Pick the hostname and create the tunnel.
2. Copy the local database and `x-token.key` to the volume, or start fresh and reconnect X.
3. Update the X developer app's callback URL to the public hostname.
4. Create the owner user, sign in, and create a new connector token for Grok Bot.
5. First connection check: confirm Grok Bot can send the bearer token, and note which transport it uses.
