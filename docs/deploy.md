# Deploy Xtend

Xtend is one container with SQLite inside a mounted volume, so any host that runs Docker will do: a small VPS, a home server, or a NAS. It needs HTTPS, a hostname, and the settings from [setup](setup.md).

Two ways to run it:

- **Kamal**, from your computer to a server over SSH. Kamal builds the image, ships it, and gets a Let's Encrypt certificate.
- **Docker Compose**, on the server itself, behind your own reverse proxy.

Either way, the `/data` volume holds both SQLite databases and `x-token.key`, which encrypts your X tokens. Back up the whole volume, together.

## Kamal

You need Docker on your computer, and a Linux server you can reach as root (or a sudo user) over SSH with your key. Point your hostname's DNS at the server first.

```sh
export XTEND_SERVER=203.0.113.10        # the server's address or SSH host alias
export XTEND_HOST=xtend.example.com     # your public hostname
export SECRET_KEY_BASE=$(bin/rails secret)
export X_CLIENT_ID=... X_CLIENT_SECRET=...

bin/kamal setup                          # installs Docker on the server and deploys
bin/kamal allow HANDLE=yourhandle        # allow your X account
```

Later deploys are `bin/kamal deploy` with the same variables set. `.kamal/secrets` reads the three secrets from your environment; you can replace each line with a password-manager command, such as `$(op read op://Private/xtend/X_CLIENT_SECRET)`. Never write raw values into it.

`config/deploy.yml` uses a registry that Kamal runs on your computer and tunnels over SSH, so you don't need a Docker Hub account. Useful aliases: `bin/kamal console`, `bin/kamal logs`, `bin/kamal shell`, `bin/kamal dbc`.

For a setup the defaults don't fit (no public ports, a tunnel, a different user), copy `config/deploy.yml` to `config/deploy.mine.yml`, edit it, set `secrets_path: .kamal/secrets.mine` in it, and pass `-c config/deploy.mine.yml` to every Kamal command. Both files are gitignored.

## Docker Compose

On the server:

```sh
git clone https://github.com/davafons/xtend.git && cd xtend
cp .env.example .env                    # fill it in; SECRET_KEY_BASE from the command in the file
docker compose up -d --build
docker compose exec xtend bin/rails users:allow HANDLE=yourhandle
```

The container listens on `127.0.0.1:3000`. Put a reverse proxy in front for HTTPS. With [Caddy](https://caddyserver.com), the whole Caddyfile is:

```
xtend.example.com {
  reverse_proxy 127.0.0.1:3000
}
```

To update: `git pull && docker compose up -d --build`. Migrations run when the container starts.

## Behind an access proxy

You can put Cloudflare Access or a similar sign-in proxy in front of Xtend for a second lock. Let these paths bypass it, because the browser extension and AI clients reach them with their own tokens:

- `/x/captures` (and `/x/captures/context`)
- `/mcp`
- `/.well-known/*`
- `/oauth/token`, `/oauth/register`, `/oauth/revoke`

`/oauth/authorize` is where you approve a connection in your browser, so it can stay behind the proxy.

## Back up and restore

Take a consistent copy of the live database without stopping the app:

```sh
bin/kamal app exec --reuse "bin/rails runner 'ActiveRecord::Base.connection.execute(%q{VACUUM INTO \"/data/backup.sqlite3\"})'"
```

Copy `/data` off the server with your usual backup tool. To restore, stop the app, put the files back in the volume, and start it again. Without `x-token.key`, saved X tokens can't be read and you sign in again; everything else is intact.

## Nothing runs on its own

Xtend has no scheduled jobs. X reads start only when you press a button, one page at a time, and AI runs only when you ask your AI client. Background jobs (Solid Queue) run inside the web process.
