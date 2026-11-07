# Deploying to the server

The app runs on the server at `https://xtend.example.com` and deploys with Kamal from this repository. The owner approves each deployment and any change to what is exposed.

## How it fits together

| Piece | Where |
| --- | --- |
| Container | Kamal runs `twitter-crm` on the server (`config/deploy.yml`). kamal-proxy listens on `127.0.0.1:23010` only, because Caddy owns ports 80 and 443. |
| Image | Built for amd64 from the working copy on this Mac and pushed to Kamal's local registry (`localhost:5555`). the server pulls it through the SSH tunnel. No public registry is involved. |
| Edge | In `../infra`, the `twitter-crm` entry in `terraform/cloudflare-service-access.tf` defines the DNS record, the server tunnel route, and Cloudflare Access with the owner's GitHub login. |
| `/mcp` | Bypasses Access and skips the browser integrity check, so Grok Bot can reach it. The app authenticates it with the workspace's connector token. |
| Data | `xtend_data` on the server, mounted at `/data`. It holds `production.sqlite3`, `production_queue.sqlite3`, and `x-token.key`, which encrypts saved X tokens. The appdata restic backup covers it. A database backup without the key can't decrypt X tokens. |
| Secrets | `SECRET_KEY_BASE`, `X_CLIENT_ID`, and `X_CLIENT_SECRET` live in SSM under `/xtend/`, and `.kamal/secrets` reads them. Keep `SECRET_KEY_BASE` stable: changing it signs everyone out and invalidates connector tokens. |

## Sign-in

Two gates, in order:

1. Cloudflare Access with the owner's GitHub login covers every path except `/mcp`.
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
8. Create a connector token in the app and give Grok Bot `https://xtend.example.com/mcp` with that token. On the first call, note which transport Grok uses.

## Background jobs

X reads run in Solid Queue inside the same Puma process, so there is one container and no separate worker. Each click queues one page read, the page refreshes until it finishes, and failed reads are never retried automatically. There are no recurring jobs.

## What is public

- Cloudflare Access protects everything except `/mcp`. Behind Access, every page still requires an app session, except `/session/new`, the X sign-in start and callback, and `/up`.
- `/mcp` is authenticated by the workspace's connector token and allows 120 requests per minute per IP. Starting X sign-in allows 10 attempts per 3 minutes per IP.
- The port is bound to the server's loopback, so nothing can bypass the tunnel. Rails trusts private proxies, so `X-Forwarded-For` gives the visitor's IP (`test/integration/proxy_test.rb`).
- The Content Security Policy only allows scripts from the app's own origin.
