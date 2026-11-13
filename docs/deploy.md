# Deploying to the server

The app runs on the server at `https://xtend.example.com` and deploys with Kamal from this repository. The owner approves each deployment and any change to what is exposed.

## How it fits together

| Piece | Where |
| --- | --- |
| Container | Kamal runs `xtend` on the server (`config/deploy.yml`). kamal-proxy listens on `127.0.0.1:23010` only, because Caddy owns ports 80 and 443. |
| Image | Built for amd64 from the working copy on this Mac and pushed to Kamal's local registry (`localhost:5555`). the server pulls it through the SSH tunnel. No public registry is involved. |
| Edge | In `../infra`, the `xtend` entry in `terraform/cloudflare-service-access.tf` defines the DNS record, the server tunnel route, and Cloudflare Access with the owner's GitHub login. |
| `/mcp`, `/x/captures`, OAuth | `/mcp`, `/x/captures`, `/.well-known`, `/oauth/token`, `/oauth/register`, and `/oauth/revoke` bypass Access (`api_prefix` and `extra_bypass_prefixes` in that entry), so AI clients and the browser extension can reach them; they also skip the browser integrity check. The app authenticates `/mcp` and `/x/captures` with OAuth access tokens (or pasted tokens) scoped to each. The approval page, `/oauth/authorize`, stays behind Access and the app session. |
| Data | `xtend_data` on the server, mounted at `/data`. It holds `production.sqlite3`, `production_queue.sqlite3`, and `x-token.key`, which encrypts saved X tokens. The appdata restic backup covers it. A database backup without the key can't decrypt X tokens. |
| Secrets | `SECRET_KEY_BASE`, `X_CLIENT_ID`, and `X_CLIENT_SECRET` live in SSM under `/xtend/`, and `.kamal/secrets` reads them. Keep `SECRET_KEY_BASE` stable: changing it signs everyone out and invalidates every OAuth and pasted token. |

## Sign-in

Two gates, in order:

1. Cloudflare Access with the owner's GitHub login covers every path except `/mcp`, `/x/captures`, and the OAuth endpoints clients call without a browser.
2. The app's own sign-in is "Sign in with X" only. Only handles allowed with `users:allow` get in; the first sign-in pins the X user ID, and the same sign-in saves the workspace's read-only X tokens. There is no signup and there are no passwords.

Each sign-in costs one X user read, which is recorded on Spending.

## Deploy

```sh
aws sso login --profile default   # .kamal/secrets reads SECRET_KEY_BASE from SSM
bin/kamal deploy
```

Kamal builds the current working copy, including jj's `@`, which isn't a git commit yet. Useful aliases: `bin/kamal logs`, `bin/kamal console`, `bin/kamal shell`.

## First-time setup

These steps run once, in order:

1. Store the secret: `aws ssm put-parameter --profile default --region us-east-1 --type SecureString --name /xtend/SECRET_KEY_BASE --value "$(openssl rand -hex 64)"`.
2. Create the data directory, owned by the container's `rails` user: `ssh the server 'install -d -o 1000 -g 1000 -m 700 xtend_data'`.
3. Store the X app as `X_CLIENT_ID` and `X_CLIENT_SECRET` in the same SSM path. In the X developer portal, add `https://xtend.example.com/x/connection/callback` to the app's callback URLs.
4. In `../infra/terraform`, run `./tf plan`, then `./tf apply`.
5. `bin/kamal setup`. This boots kamal-proxy on loopback and deploys the app.
6. Allow the owner: `bin/kamal app exec "bin/rails users:allow HANDLE=yourhandle"`, then sign in with X.
7. To keep local data instead, copy the local database and `x-token.key` into the data directory before step 5.
8. Add `https://xtend.example.com/mcp` to the assistant as a custom connector; it registers itself and opens Xtend for approval. For a client without OAuth, create a pasted token under AI and send it as a bearer header.

## Background jobs

X reads run in Solid Queue inside the same Puma process, so there is one container and no separate worker. Each click queues one page read, the page refreshes until it finishes, and failed reads are never retried automatically. There are no recurring jobs.

## What is public

- Cloudflare Access protects everything except `/mcp`, `/x/captures`, `/.well-known`, `/oauth/token`, `/oauth/register`, and `/oauth/revoke`. Behind Access, every page still requires an app session, except `/session/new`, the X sign-in start and callback, and `/up`.
- `/mcp` takes an access token with the `mcp` scope and allows 120 requests per minute per IP. `/x/captures` takes one with the `capture` scope, accepts only browser-extension origins, and allows 60 requests per minute per IP. Starting X sign-in allows 10 attempts per 3 minutes per IP. `/oauth/token` allows 60 requests per minute and `/oauth/register` 10 per hour per IP; a registration grants nothing until the owner approves it, and unapproved ones are pruned after a day.
- The port is bound to the server's loopback, so nothing can bypass the tunnel. Rails trusts private proxies, so `X-Forwarded-For` gives the visitor's IP (`test/integration/proxy_test.rb`).
- The Content Security Policy only allows scripts from the app's own origin.
