# Twitter CRM

A Rails app for finding useful builder conversations, remembering people, and reviewing follows. It started as a local POC and now has sign-in and per-workspace data so it can be deployed (see [deploy](docs/deploy.md) and [architecture plan](docs/architecture-plan.md)). The shared components come directly from the sibling `lostcoords-ui` gem. Project structure follows WariWari: Rails models and REST controllers, ERB, Hotwire, Importmap, Propshaft, SQLite, and standalone Tailwind.

## Run with Parcela

Requirements: Ruby 4.0.2, Bundler, and Parcela. The `lostcoords-ui` 0.7.0 gem comes from GitHub.

```bash
bundle install
bin/dev --detach
parcela url web
```

The review URL is `https://twitter-crm.localhost`. `parcela status` shows Rails and the CSS watcher. `parcela logs web` shows application logs. `parcela down` stops this environment.

Every page requires sign-in. Create your account once per database, typing the password when asked:

```bash
PARCELA_DATA_DIR=~/.local/state/parcela/environments/<id>/data bin/rails users:create EMAIL=you@example.com
```

`parcela ls` shows the environment ID. `parcela run` can't be used while the environment is up, because it holds the environment lock. The first user joins the existing workspace and its data.

Parcela runs database preparation and the Tailwind build before startup. SQLite lives in `PARCELA_DATA_DIR` when provided, otherwise `storage/`. Real mode starts empty and makes no X requests.

## What works

- Today shows English candidate tweets with person context, pins, skip and one-day snooze controls.
- Opening a source tweet does not count as replying. A manual reply report remains unverified and stays separate from confirmed progress.
- Source-backed reply ingestion creates or updates the person and maintains all-history reply states. Initial replies to distinct targets count once. Continuations, repeats, self-replies, and unresolved classifications cannot inflate outreach progress.
- Notes, pins, and keep-following records persist independently of source updates.
- Follow review excludes mutuals, explicit keeps, and anyone with a direct reply in either direction. It needs a complete fresh follower snapshot. A manual unfollow report does not rewrite X relationship facts.
- Data settings allow builder-interest edits, bounded candidate-file import, and a Grok context download that excludes notes and DMs.

## Current integration boundary

Single-owner X OAuth uses Authorization Code + PKCE S256 and read-only scopes. It verifies the connected account through `/2/users/me`, supports refresh and local disconnect, and stores tokens encrypted in SQLite. X OAuth is separate from signing in to the app.

Bounded manual collection, a spend ledger, recent search, and follower-change tracking are implemented. Full archive ingestion, backup restore, background sync jobs, and a live MCP connection are not implemented. Connecting does not start collection. The identity check can consume a user-read credit when a real connection is initiated. This POC never posts or unfollows on X.

The existing Birdclaw checkout was considered as a data foundation. Its documented first live sync requires an archive, so it does not provide the archive-independent first slice. A future adapter can reuse its public interfaces after checking the real export and coverage semantics. This app does not open Birdclaw personal databases or use its private browser transport.

## Candidate import

Upload JSON on Discover. The format is `twitter-crm-discovery-v1`, with up to 200 posts and a 1 MB limit. Each post has `x_id`, `body`, `published_at` in ISO-8601, optional `language`, `topic`, `match_reason`, and a `person` object containing numeric-string `x_id`, `handle`, `name`, and optional `description`.

Imports are transactional and idempotent by stable IDs. They cannot submit verified replies or follow memberships. Existing private notes, pins, and keep choices survive profile enrichment. Invalid data rolls back the entire file.

## Isolated demo

The demo is opt-in and uses a different SQLite file. It contains fictional people, tweets, source evidence, and follow snapshots, and displays a persistent demo banner. Links to X are disabled for fictional content.

```bash
CRM_DEMO=1 bin/rails db:prepare demo:seed
```

With a Parcela data directory, pass the same `PARCELA_DATA_DIR` to that command. Serving the demo requires starting the web process with `CRM_DEMO=1`; the running real workspace does not change. `demo:seed` refuses to run in real mode. It does not overwrite an existing demo or contact X. Create a user in the demo database too (`CRM_DEMO=1 bin/rails users:create EMAIL=...`).

## Verify

```bash
bin/rails test
bin/rails tailwindcss:build
bin/rails zeitwerk:check
```

Tests exercise domain behavior and HTTP persistence, including populated demo rendering, sign-in on every route, and workspace isolation. Desktop layout is checked in the running Parcela browser, rather than asserted through HTML selector tests.

The [POC specification](docs/poc-spec.md) defines intended scope. The [cost calculator](scripts/estimate-x-costs.py) is a planning tool; displayed allowances do not configure X billing controls.

New workspaces default to a **$10 monthly API allowance**. Existing saved allowances stay unchanged until explicitly edited on Spending. Enter integer USD cents (`1000` means `$10.00`). This local setting cannot verify or change the X console billing-cycle cap or report actual provider spend; use the X developer console for those controls. Graph and discovery reads start only through explicit manual actions and require a current billing-cycle observation.

## Connect your personal X account

Create or inspect your own developer app in the X console. Enable OAuth 2.0 and the read scopes `tweet.read users.read follows.read offline.access`. A confidential web app also requires its client secret.

On **Settings**, use the **X developer app** form to save the OAuth Client ID, masked Client Secret, and exact redirect URI. The configuration is encrypted locally under a purpose separate from account tokens. Saved secrets are never rendered into the form or included in context exports. A blank secret preserves the saved value only for the same Client ID; use the explicit removal checkbox to clear it.

Environment configuration remains supported through `X_CLIENT_ID`, optional `X_CLIENT_SECRET`, and `X_REDIRECT_URI`. Alternatively run `bin/rails credentials:edit` and add an `x` mapping with `client_id`, `client_secret`, and `redirect_uri`. Precedence is environment, Rails credentials, then local form. A Client ID selects the whole source, so an environment client cannot accidentally use a different app's saved secret. Never put values in chat or commit plaintext keys.

Disconnect an active X connection locally before changing saved client configuration. Saving configuration invalidates pending OAuth attempts, and a configuration fingerprint prevents an in-flight old callback from saving mismatched credentials.

The callback route is `/x/connection/callback`. The personal development app has successfully authorized with `https://twitter-crm.localhost/x/connection/callback` and completed its identity check. For another developer app, register exactly its configured full URL in the X console, and open the local app at that same origin before pressing **Connect X**. The URI remains configurable; no public tunnel is created.

Restart the app after changing process environment. Settings displays the exact configured callback and keeps **Connect X** disabled until configuration is present and valid. The callback verifies state, expiry, one-time use and account identity. Once bound, a different X account cannot replace the owner or its data.

Saved tokens use AES-256-GCM with a separate owner-readable key at `PARCELA_DATA_DIR/x-token.key`, falling back to `storage/x-token.key`. Back up that key securely with the encrypted database if retaining the connection. It is excluded from exports and version control. **Disconnect locally** deletes token records while preserving relationship data; revoke the app in X settings to remove the provider authorization.

**Check connection** refreshes an expiring token if necessary and fetches only account identity. It never triggers graph or search collection. OAuth behavior is tested with mock HTTP, not a live paid account.

The initial token response may omit `scope` when it is unchanged, as permitted by [OAuth RFC 6749 section 5.1](https://www.rfc-editor.org/rfc/rfc6749#section-5.1). The app then retains the exact requested read scopes. Explicit extra or missing required scopes are still rejected.

## Use the connected workspace

Open **Spending** for the provider-cycle observation and remaining allowance, and **X data** for source coverage and recent page results. Each collection action reads one bounded page. **Read next page** continues that source, and duplicate submissions cannot refetch an already committed page.

Use **Refresh follower baseline** before cleanup when follower data is more than 24 hours old. Its completed result also updates Followers. The first snapshot is a baseline, so loss dates and follower lifetimes appear only after later observations. See [follower metrics](docs/follower-metrics.md).

For Grok discovery, copy the prepared prompt, then paste its public source URLs. **Resolve saved links** verifies up to 20 posts. **Resolve people** fills missing author identities separately. A bounded direct-search option is also available. **Refresh saved matches** re-ranks collected posts without API calls.

Write replies on X and use **Check sent replies** to confirm them. The collector ends its query window fifteen seconds before the check, so a just-sent reply may need a later refresh. Historical backfill and follow-ups never create additional outreach slots.

The first collection trial remains limited to $5 inside the $10 cycle allowance. Provider observations are manual and can lag. Failed requests retain conservative holds, and other apps may share the provider account. There is no scheduled collection or automatic top-up.

Gemfile pins the sibling UI source to its last working revision while its current checkout is being refactored. Update that revision only after its helpers and Tailwind build pass this app's checks. The [implementation status](docs/implementation-status.md) records the live trial and remaining gaps.

## Visual theme

The interface is dark only and uses the default `lostcoords-ui` dark theme, as on its docs site. The app sets no color tokens of its own. Shared Heroicons and text labels mark relationship and action cues.
