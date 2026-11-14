# Xtend

Guidance for anyone, human or coding agent, working on this repository. If a `CLAUDE.local.md` or `AGENTS.local.md` exists at the root, it holds the maintainer's own deployment and account rules: follow it too. Both are gitignored.

## Product and scope

- Xtend is a self-hosted personal CRM for X. One owner signs in with X; all owner data is scoped to a workspace. `README.md` describes the features, and `docs/` covers setup, deployment, data, and the AI connector.
- Every page requires sign-in except `/session/new` and `/up`. `/mcp` and `/x/captures` (captures in, and the extension's read-only context for handles on x.com out) take OAuth access tokens (or pasted tokens) scoped to one of them, issued by the app's own OAuth 2.1 server (`Oauth::`: discovery, dynamic registration, PKCE, refresh rotation). Its records are auth records like sessions, not `WorkspaceScoped`.
- Signing in with X is the only way in, and it also connects that workspace's read-only X data. There is no signup: `bin/rails users:allow HANDLE=...` adds an allowed X account, which is pinned to its X user ID on first sign-in, and `users:revoke` removes it. The X app is app-wide, from the environment or Rails credentials.
- If an access proxy such as Cloudflare Access sits in front of the app, `/mcp`, `/x/captures`, `/.well-known`, and `/oauth/{token,register,revoke}` must bypass it so AI clients and the extension can reach them. `/oauth/authorize` stays behind it.
- Include `WorkspaceScoped` in every new owner-data model; its default scope raises without `Current.workspace`, so tasks, scripts, and tests must set one. Uniqueness on X IDs and handles is per workspace.
- Target a computer browser, English discovery, and replies on 20 distinct new target posts per session. Follow-up messages cannot inflate progress.
- Replying, following, and unfollowing happen manually on X. AI assistants connect only through `/mcp`: any MCP client may connect. They read Xtend and write only to its own records: tags, notes, reminders, recaps, profile facts, post drafts, and unverified reply targets (`AI::Proposal` logs each change). With the owner's "AI applies changes" setting on (the default), changes apply at once and each can be undone; off, they wait for acceptance. AI never removes or edits the owner's own tags or notes, and never posts, follows, unfollows, or messages on X. Xtend's AI tasks are MCP prompts (`Mcp::Prompts`, also via `get_task`), so the app offers a "Run the Xtend task …" request to copy, never a full prompt or a paste box. Code and UI both call them AI (`AI::`, the `ai` color, `source: "ai"`). MCP text refers to the owner generically, never by a real name.
- Confirmed replies create or update person records automatically. Preserve manual pins, keep-following choices, tags, and notes during sync. AI tags carry `source: "ai"` and only ever add to the owner's.
- Follow status, observed reply state, history coverage, and user preferences are separate facts. Use all available reply history.
- Cleanup never suggests explicit keeps. Mutuals are included by default and always marked; leaving them out needs fresh follower data, because partial or stale follower data cannot establish a current non-mutual. Missing interaction history is not proof of never interacting, and an unknown last post is never "inactive".
- Data comes from the browser extension's captures, the X archive import, and bounded read-only X API reads with a spend ledger. Archive import never stores DM text. Default real mode must show honest coverage and empty/setup states. Opt-in demo data must be labeled and isolated from real data.

## Rails and UI

- Conventional Rails: rich models, thin RESTful controllers, ERB, Hotwire, SQLite, Importmap, and Propshaft. Avoid service-object, presenter, and repository layers without a concrete need, and keep dependencies small.
- Use the `lostcoords-ui` gem pinned in the Gemfile, through its rendering helpers, theme tokens, and Tailwind entry. Avoid copied component class lists, app-local primitive reimplementations, or a separate JavaScript framework. A generic component the gem lacks belongs in the gem, not here.
- The theme is dark only (`data-theme="dark"`). The palette is set per user and written as `data-palette` on `<html>`; today the only one is `dim`. Palettes override library tokens only in `app/assets/tailwind/tokens.css`, scoped to `html[data-palette=...]`. Color carries meaning only through the app colors in `tokens.css`: `you` (your actions), `like`, `message` (DMs), and `ai` (anything an AI wrote or proposed), plus library `success` for two-way and `warning` for one-way from them. Each tag keeps a stable hue. Avatars carry a ring in their follow relationship's color. The one accent is `--xtend-accent` as `primary`: actions, links, tabs, the current page, and the wordmark. It is not a meaning color, and there are no gradients. Cards have no outline. Inside a card use `bg-tile` for inset panels. Use borders only for table and list rules. Keep shared Heroicons and text labels for relationship and action cues.
- Draw charts with the `chart` helper (`ChartsHelper`) and its Stimulus controller, built on Chart.js. Series take meaning colors, a missing value stays `nil` so it draws as a gap, and every chart keeps its hover tooltip, legend, and screen-reader table.
- Code is grouped by domain: `X::` (API, OAuth, reads, sync, captures, archive), `Follow::` (snapshots and cleanup), `AI::` (research and proposals from any AI client), `Outreach::` (reply candidates, ranking, counted targets, sessions, and the growth plan), `Mcp::`, and `Network::` (the graph and timeline built from saved data), with core models at the top level. Put new code in the matching namespace.

## Verification and local operation

- `bin/dev` runs the app with Parcela; `bin/dev --detach` keeps it running and `parcela url web` prints its HTTPS URL. Startup checks gems, prepares the SQLite database, builds Tailwind, and starts Rails plus the CSS watcher. It does not seed demo data or call X.
- Test domain behavior with Minitest, including reply direction, distinct outreach targets, duplicate ingestion, automatic person records, manual preferences surviving sync, and cleanup exclusions. Run `bin/rails test`.
- Verify UI changes in a desktop browser. Tests should assert behavior; screenshots establish layout and copy.
- Keep local servers on loopback. X reads run as Solid Queue jobs inside Puma (`X::FetchPageJob`), one page per explicit action, with no automatic retries. Keep `config/recurring.yml` empty: nothing collects or runs AI on a schedule.
- Never log or commit credentials, personal deployment settings, or personal data. A demo, fixture, or empty configuration must not imply successful OAuth or paid sync.
- Respect the workspace's spending allowance for X API reads. Estimates stay distinct from actual provider billing, which only the X developer console reports.
- Report exact run commands, checks performed, and remaining gaps. Do not describe a feature as implemented until it runs.
- Do not add AI co-author trailers or AI attribution to commits or pull request descriptions.
