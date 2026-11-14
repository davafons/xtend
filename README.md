<p align="center">
  <img src="public/icon.png" width="96" height="96" alt="">
</p>

<h1 align="center">Xtend</h1>

<p align="center">
  <a href="https://rubyonrails.org"><img src="https://img.shields.io/badge/Rails-8.1-b45d3c?logo=rubyonrails&amp;logoColor=white" alt="Rails 8.1"></a>
  <a href="https://www.ruby-lang.org"><img src="https://img.shields.io/badge/Ruby-4.0-b45d3c?logo=ruby&amp;logoColor=white" alt="Ruby 4.0"></a>
</p>

<p align="center">
  Remember the people you talk with on X, and grow by replying well.
</p>

<p align="center">
  <a href="docs/features.md">Features</a> ·
  <a href="extension/README.md">Browser extension</a> ·
  <a href="docs/grok-mcp-plan.md">AI connector</a> ·
  <a href="docs/deploy.md">Deploy</a>
</p>

Xtend is a personal CRM for X. It keeps a record of everyone you reply to, who replies back, who follows whom, and what each reply brought, then helps you choose the next conversations worth having. Replying, following, and unfollowing stay manual on X: Xtend never posts or acts for you.

It's a Rails 8.1 app with Hotwire, SQLite, and the [lostcoords-ui](https://github.com/lostcoords/ui) components. One person signs in with X; their data lives in a workspace of its own.

## What it does

- **Outreach.** A reply session of 20 new posts, ranked by what past replies brought (account size, the people who paid off) and by whether now is a busy hour for your audience. Follow-ups in an existing exchange don't count toward it.
- **People.** Every person you replied to becomes a record automatically, with replies both ways, likes, follows, tags, notes, pins, and reminders. Sync never overwrites what you set by hand.
- **Growth.** A follower goal with weekly checkpoints, a checklist Xtend ticks from your replies, posts, and analytics, and your circle: the people you want to be seen by, and who you haven't replied to this week.
- **Week in review and Insights.** What you did, what it brought (impressions, profile visits, follows from X's own analytics), your best reply and post, and who has gone quiet.
- **Network and Timeline.** Who talks with whom among the people you know, built from what you've seen.
- **Follow review.** Accounts worth unfollowing, never including explicit keeps or anyone you've exchanged replies with. Mutuals are included and marked. It needs a fresh, complete follower list, because missing history isn't proof you never interacted.
- **Compose.** Post ideas and drafts.

## Where the data comes from

- **The browser extension.** [Xtend Capture](extension/README.md) copies what x.com already loaded while you browse: timelines, profiles, follow lists, notifications, and your X analytics. It makes no requests to X. On x.com it also shows what Xtend knows: a relationship ring on avatars, badges by names, a card on profiles, and a panel above the reply box.
- **Read-only X API.** Optional, bounded, one page per explicit action, with a spend ledger and a monthly allowance. Nothing runs on a schedule.
- **An X archive.** One-to-one DM metadata only: who and when, never the text.

Every page says how complete its data is. Missing data shows as missing, not zero.

## Connect an AI

Xtend is an MCP server at `/mcp`, with its own OAuth 2.1 sign-in, so any MCP client can connect: Grok, Claude, ChatGPT, or your editor's agent.

```sh
claude mcp add --transport http xtend https://your-xtend-host/mcp
```

The AI reads your people, replies, network, and analytics, and runs Xtend's tasks as MCP prompts: `tag_people`, `review_follows`, `research_person`, `weekly_review`, `what_works`, `post_ideas`, and `find_reply_targets`. It can write only to Xtend's own records (tags, notes, reminders, recaps, profile facts, post drafts, and reply targets), and each change can be undone. Turn off **AI applies changes** to review each one first. An AI never posts, follows, unfollows, or messages on X.

## Run it locally

You need Ruby 4.0.2, Bundler, [Parcela](https://github.com/lostcoords/parcela), and an X developer app with OAuth 2.0 and the read scopes `tweet.read users.read follows.read offline.access`.

```sh
bundle install
bin/dev --detach
parcela url web     # https://xtend.localhost
```

Set the X app with `X_CLIENT_ID`, `X_CLIENT_SECRET`, and `X_REDIRECT_URI`, or under `x:` in Rails credentials. Signing in with X is the only way in, and there's no signup. Allow your account first:

```sh
PARCELA_DATA_DIR=~/.local/state/parcela/environments/<id>/data bin/rails users:allow HANDLE=yourhandle
```

`parcela ls` shows the environment ID. A new workspace starts empty and makes no X requests.

To try it without X, seed the isolated demo, which uses its own database and a labeled banner:

```sh
XTEND_DEMO=1 bin/rails db:prepare demo:seed
```

Then start the web process with `XTEND_DEMO=1`.

## Load the extension

Open `chrome://extensions` (or `brave://extensions`), turn on **Developer mode**, choose **Load unpacked**, and pick the `extension/` folder. Connect it to Xtend from its options page. After pulling changes, press reload on the extension.

## Check it

```sh
bin/rails test
bin/rails zeitwerk:check
```

Tests cover the domain rules: reply direction, distinct outreach targets, duplicate ingestion, automatic person records, manual choices surviving sync, and cleanup exclusions. Layout is checked in a browser.

## Documentation

- [Features](docs/features.md) and the [POC specification](docs/poc-spec.md)
- [Architecture plan](docs/architecture-plan.md) and [data access](docs/data-access.md)
- [Follower metrics](docs/follower-metrics.md) and [X API costs](docs/api-costs.md)
- [AI connector](docs/grok-mcp-plan.md)
- [Deploy with Kamal](docs/deploy.md)
- [Implementation status](docs/implementation-status.md)
