# Deploying to the server

Nothing has been deployed yet. This page lists what a deployment needs. The owner approves the host details before anything is exposed.

## What the app expects

| Setting | Purpose |
| --- | --- |
| `APP_HOSTS` | Comma-separated public hostnames, such as `crm.example.com`. The server won't boot without it, and other `Host` headers get 403. |
| `SECRET_KEY_BASE` | Signs sessions and hashes connector tokens. Generate it with `openssl rand -hex 64` and keep it stable: changing it signs everyone out and invalidates connector tokens. |
| `/data` volume | Holds `production.sqlite3`, the job queue in `production_queue.sqlite3`, and `x-token.key`, which encrypts saved X tokens. Back up both together. A database backup without the key can't decrypt X tokens. |
| TLS in front | The app assumes HTTPS (`assume_ssl`, `force_ssl`, secure cookies, HSTS). Cloudflare Tunnel terminates TLS and forwards to port 3000. |
| X developer app | Each workspace saves its own X app in Settings. Its callback must be `https://<host>/x/connection/callback`. Owned-rate pricing only applies to the owner's own app. |

## Build and run on the server

The existing the server tunnel from `../infra` (`tunnel-docker`, with `cloudflared` on the host network) carries the traffic. This app publishes only `127.0.0.1:23010` (`compose.yaml`), and the tunnel routes the public hostname there. These changes belong in infra, made there rather than from this repo:

1. Terraform: add an ingress entry to `cloudflare_zero_trust_tunnel_cloudflared_config.the server`, before the catch-all, routing `hostname = "<name>.example.com"` to `service = "http://localhost:23010"`. Also add the matching DNS record.
2. Ansible: add a `twitter-crm` stack for the server that runs this `compose.yaml` with `APP_HOSTS` and `SECRET_KEY_BASE` from SSM, for example under `/xtend/`.
3. Build the image, then create the owner:

```sh
docker build -t twitter-crm .
docker compose exec web ./bin/rails users:create EMAIL=you@example.com
```

`users:create` asks for the password without echoing it. `users:password EMAIL=...` changes a password and signs out that user's sessions. There is no signup page.

Cloudflare terminates TLS. Requests reach the container from Docker's private bridge address, and Rails trusts private proxies, so `X-Forwarded-For` gives the visitor's IP and rate limits count each visitor separately. `test/integration/proxy_test.rb` covers this. The port is bound to loopback, so nothing outside the server can bypass the tunnel and fake that header.

Optional extra layer: a Cloudflare Access policy on every path except `/mcp` and `/up` adds a second login in front of the app. Grok Bot can't pass Access, so `/mcp` has to stay outside the policy.

The `lostcoords-ui` gem is pinned to the 0.7.0 commit on GitHub (`lostcoords/ui`), so the image builds anywhere with network access.

## Background jobs

X reads run in Solid Queue inside the same Puma process, so there is one container and no separate worker. Each click queues one page read, the page refreshes until it finishes, and failed reads are never retried automatically. There are no recurring jobs.

## What is public

- Every page requires a signed-in session, except `/session/new` and `/up`.
- `/mcp` is authenticated by the workspace's connector token, not by a session. Grok Bot uses `https://<host>/mcp` with that token.
- Sign-in allows 10 attempts per 3 minutes per IP. `/mcp` allows 120 requests per minute per IP.
- The Content Security Policy only allows scripts from the app's own origin.

## Before exposing it

1. Pick the hostname, then add its ingress rule and the stack in infra.
2. Copy the local database and `x-token.key` to the volume, or start fresh and reconnect X.
3. Update the X developer app's callback URL to the public hostname.
4. Create the owner user, sign in, and create a new connector token for Grok Bot.
5. First connection check: confirm Grok Bot can send the bearer token, and note which transport it uses.
