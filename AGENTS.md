# Twitter CRM

## Product and scope

- Build the Rails POC defined in `docs/poc-spec.md`. `PRD.md` defines detailed metric meanings; other feature documents include later options.
- The app is moving from a local POC to a deployable app (see `docs/architecture-plan.md`). Every page requires sign-in except `/session/new` and `/up`; `/mcp` uses its workspace's connector token. There is no public signup: `bin/rails users:create` and `users:password` manage accounts. X OAuth authorizes access to a workspace's X data; it is not app authentication.
- All owner data is scoped to a workspace. Include `WorkspaceScoped` in every new owner-data model; its default scope raises without `Current.workspace`, so tasks, scripts, and tests must set one. Uniqueness on X IDs and handles is per workspace. Today there is one owner per workspace.
- Target a computer browser, English discovery, and replies on 20 distinct new target tweets per session. Follow-up messages cannot inflate progress.
- Replying and unfollowing happen manually on X. Grok Bot is the only AI integration.
- Confirmed replies create or update person records automatically. Preserve manual pins, keep-following choices, and notes during sync.
- Follow status, observed reply state, history coverage, and user preferences are separate facts. Use all available reply history.
- Protect mutuals and explicit keeps during cleanup. Partial or stale follower data cannot establish a current non-mutual. Missing interaction history is not proof of never interacting.
- Read-only X OAuth, bounded manual graph/history collection, and the spend ledger are implemented. Archive import covers one-to-one DM metadata only (sender and time, never text). The MCP connector (`/mcp`, see `docs/grok-mcp-plan.md`) works locally; Grok Bot reaches it only once the app is deployed (`docs/deploy.md`), so until then Grok results arrive by pasted JSON. Default real mode must show honest coverage and empty/setup states. Opt-in demo data must be labeled and isolated from real data.

## Rails and UI

- Use `../wariwari` as a read-only Rails reference: conventional Rails, rich models, thin RESTful controllers, ERB, Hotwire, SQLite, Importmap, and Propshaft.
- Use the actual `lostcoords-ui` gem from `../lostcoords-ui` for shared components. Gemfile pins its last working revision while the sibling checkout undergoes a foundation refactor. Use the Bundler-resolved README and helper API; do not patch or copy sibling components.
- Use the gem's rendering helpers, theme tokens, and Tailwind entry. Avoid copied component class lists, app-local primitive reimplementations, or a separate JavaScript framework.
- Use Sanzo Wada combination 267 from https://colors.bible/#c=Blue~267 plus white. Derive theme tints and shades from the four `--wada-267-*` source tokens. Keep shared Heroicons and text labels for relationship and action cues.
- Code is grouped by domain: `X::` (API, OAuth, reads, sync), `Follow::` (snapshots and cleanup), `Grok::`, `Discovery::`, and `Mcp::`, with core CRM models at the top level. Put new code in the matching namespace.
- Follow the installed/reference Ruby and Rails versions. Keep dependencies small and avoid service-object, presenter, and repository layers without a concrete need.
- Do not modify sibling projects to make this application work.

## Verification and local operation

- `bin/dev` runs the configured Parcela environment; use `bin/dev --detach` to keep it running and `parcela url web` to retrieve its HTTPS URL. Startup checks installed gems, prepares the environment's SQLite database, builds Tailwind, and starts Rails plus the CSS watcher. It does not seed demo data or call X.
- Test domain behavior with Minitest, including reply direction, distinct outreach targets, duplicate ingestion, automatic person records, manual preferences surviving sync, and cleanup exclusions.
- Verify the runnable desktop UI in the configured browser. Tests should assert behavior; screenshots establish layout and copy.
- Keep local servers on loopback. Deploying to the server or exposing any endpoint needs the owner's explicit approval each time; `docs/deploy.md` lists the requirements. Do not activate recurring jobs as part of an ordinary local build.
- Never log or commit credentials. A demo, fixture, or empty configuration must not imply successful OAuth or paid sync.
- Respect configured resource and spending limits for live operations. The user-selected ceiling is $10 per X billing cycle, with the first collection trial capped at $5 inside that allowance. The provider cap and local allowance are set to $10, and read-only OAuth and graph/history reads have been verified live. Owned-rate evidence is recorded from the first trial; estimates remain distinct from actual provider billing. The provider cap is account-wide, so other integrations may consume it.
- Report exact run commands, checks performed, and remaining integration gaps. Do not describe a feature as implemented until it runs.

## Version control

- Check for `.jj/` at the repository root before version-control commands. If present, use jj, including in colocated repositories. Never mutate Git there or fall back to Git after a jj failure.
- Use `jj diff --git` for diffs and `jj push` for authorized pushes. Use Git only in repositories without `.jj/`.
- Do not add AI co-author trailers or AI attribution to commits or pull request descriptions.
