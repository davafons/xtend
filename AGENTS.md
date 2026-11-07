# Twitter CRM

## Product and scope

- Build the Rails POC defined in `docs/poc-spec.md`. `PRD.md` defines detailed metric meanings; other feature documents include later options.
- The app is moving from a local POC to a deployable app (see `docs/architecture-plan.md`). Every page requires sign-in except `/session/new` and `/up`; `/mcp` uses its workspace's connector token and `/x/captures` its capture token. Signing in with X is the only way in, and it also connects that workspace's read-only X data. There is no signup: `bin/rails users:allow HANDLE=...` adds an allowed X account, which is pinned to its X user ID on first sign-in, and `users:revoke` removes it. The X app is app-wide, from the environment or Rails credentials. In production, Cloudflare Access sits in front of everything except `/mcp`.
- All owner data is scoped to a workspace. Include `WorkspaceScoped` in every new owner-data model; its default scope raises without `Current.workspace`, so tasks, scripts, and tests must set one. Uniqueness on X IDs and handles is per workspace. Today there is one owner per workspace.
- Target a computer browser, English discovery, and replies on 20 distinct new target tweets per session. Follow-up messages cannot inflate progress.
- Replying and unfollowing happen manually on X. Grok Bot is the only AI integration.
- Confirmed replies create or update person records automatically. Preserve manual pins, keep-following choices, tags, and notes during sync. Grok only proposes tags; they apply when the owner accepts.
- Follow status, observed reply state, history coverage, and user preferences are separate facts. Use all available reply history.
- Protect mutuals and explicit keeps during cleanup. Partial or stale follower data cannot establish a current non-mutual. Missing interaction history is not proof of never interacting.
- Read-only X OAuth, bounded manual graph/history collection, and the spend ledger are implemented. Archive import covers one-to-one DM metadata only (sender and time, never text). The MCP connector (`/mcp`, see `docs/grok-mcp-plan.md`) works locally; Grok Bot reaches it only once the app is deployed (`docs/deploy.md`), so until then Grok results arrive by pasted JSON. Default real mode must show honest coverage and empty/setup states. Opt-in demo data must be labeled and isolated from real data.

## Rails and UI

- Use `../wariwari` as a read-only Rails reference: conventional Rails, rich models, thin RESTful controllers, ERB, Hotwire, SQLite, Importmap, and Propshaft.
- Use the actual `lostcoords-ui` gem. Gemfile pins the v0.8.2 tag from GitHub (`lostcoords/ui`); `../lostcoords-ui` is a read-only reference for its README and docs. Use the Bundler-resolved README and helper API; do not patch or copy sibling components.
- Use the gem's rendering helpers, theme tokens, and Tailwind entry. Avoid copied component class lists, app-local primitive reimplementations, or a separate JavaScript framework.
- The theme is dark only and uses the library's default dark theme unchanged (`data-theme="dark"`, as on the lostcoords-ui docs site). Do not override its color tokens in `app/assets/tailwind/tokens.css`. Color carries meaning only through the app colors in `tokens.css`: `you` (blue, your actions), `like` (pink), `message` (violet, DMs), and `grok` (teal), plus library `success` for two-way and `warning` for one-way from them. Each tag keeps a stable hue. Avatars carry a ring in their follow relationship's color. The one decorative exception is the signature gradient (you → grok → like, `.crm-signature-*` in `tokens.css`), used only on the wordmark and the active navigation item. Beyond that, color comes from people's own X avatars and banners, not from decoration. Cards have no outline. Inside a card use `bg-tile` for inset panels, not `bg-background` or ad hoc grays. Use borders only for table and list rules. Keep shared Heroicons and text labels for relationship and action cues.
- Code is grouped by domain: `X::` (API, OAuth, reads, sync), `Follow::` (snapshots and cleanup), `Grok::`, `Discovery::`, `Mcp::`, and `Network::` (the graph and timeline built from saved data), with core CRM models at the top level. Put new code in the matching namespace.
- Follow the installed/reference Ruby and Rails versions. Keep dependencies small and avoid service-object, presenter, and repository layers without a concrete need.
- Do not modify sibling projects to make this application work.

## Verification and local operation

- `bin/dev` runs the configured Parcela environment; use `bin/dev --detach` to keep it running and `parcela url web` to retrieve its HTTPS URL. Startup checks installed gems, prepares the environment's SQLite database, builds Tailwind, and starts Rails plus the CSS watcher. It does not seed demo data or call X.
- Test domain behavior with Minitest, including reply direction, distinct outreach targets, duplicate ingestion, automatic person records, manual preferences surviving sync, and cleanup exclusions.
- Verify the runnable desktop UI in the configured browser. Tests should assert behavior; screenshots establish layout and copy.
- Keep local servers on loopback. Deploying to the server or exposing any endpoint needs the owner's explicit approval each time; `docs/deploy.md` lists the requirements. X reads run as Solid Queue jobs inside Puma (`X::FetchPageJob`), one page per explicit action, with no automatic retries. Keep `config/recurring.yml` empty unless the owner approves a recurring job.
- Never log or commit credentials. A demo, fixture, or empty configuration must not imply successful OAuth or paid sync.
- Respect configured resource and spending limits for live operations. The user-selected ceiling is $10 per X billing cycle, with the first collection trial capped at $5 inside that allowance. The provider cap and local allowance are set to $10, and read-only OAuth and graph/history reads have been verified live. Owned-rate evidence is recorded from the first trial; estimates remain distinct from actual provider billing. The provider cap is account-wide, so other integrations may consume it.
- Report exact run commands, checks performed, and remaining integration gaps. Do not describe a feature as implemented until it runs.

## Version control

- Check for `.jj/` at the repository root before version-control commands. If present, use jj, including in colocated repositories. Never mutate Git there or fall back to Git after a jj failure.
- Use `jj diff --git` for diffs and `jj push` for authorized pushes. Use Git only in repositories without `.jj/`.
- Do not add AI co-author trailers or AI attribution to commits or pull request descriptions.
