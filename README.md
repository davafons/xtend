<p align="center">
  <img src="public/icon.png" width="96" height="96" alt="">
</p>

<h1 align="center">Xtend</h1>

<p align="center">
  <a href="https://rubyonrails.org"><img src="https://img.shields.io/badge/Rails-8.1-b45d3c?logo=rubyonrails&amp;logoColor=white" alt="Rails 8.1"></a>
  <a href="https://www.ruby-lang.org"><img src="https://img.shields.io/badge/Ruby-4.0-b45d3c?logo=ruby&amp;logoColor=white" alt="Ruby 4.0"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-57966f" alt="License: MIT"></a>
</p>

<p align="center">
  Remember the people you talk with on X, and grow by replying well.
</p>

<p align="center">
  <a href="docs/setup.md">Setup</a> ·
  <a href="docs/deploy.md">Deploy</a> ·
  <a href="extension/README.md">Browser extension</a> ·
  <a href="docs/ai.md">Connect an AI</a>
</p>

Xtend is a personal CRM for X that you host yourself. It keeps a record of everyone you reply to, who replies back, who follows whom, and what each reply brought, then helps you choose the next conversations worth having. Replying, following, and unfollowing stay manual on X: Xtend never posts or acts for you.

It's a Rails 8.1 app with Hotwire and SQLite in a single container. One person signs in with X, with an X developer app of their own.

## What it does

- **Outreach.** A reply session of 20 new posts, ranked by what past replies brought (account size, the people who paid off) and by whether now is a busy hour for your audience. Follow-ups in an existing exchange don't count toward it.
- **People.** Everyone you reply to becomes a record automatically, with replies both ways, likes, follows, tags, notes, pins, and reminders. Syncs never overwrite what you set by hand.
- **Growth.** A follower goal with weekly checkpoints, a checklist Xtend ticks from your replies, posts, and analytics, and your circle: the people you want to be seen by, and who you haven't replied to this week.
- **Week in review and Insights.** What you did, what it brought (impressions, profile visits, follows from X's own analytics), your best reply and post, and who has gone quiet.
- **Network and Timeline.** Who talks with whom among the people you know, built from what you've seen.
- **Follow review.** Accounts worth unfollowing, never including ones you chose to keep or anyone you've exchanged replies with. It needs a fresh, complete follower list first, because missing history isn't proof you never interacted.
- **Compose.** Post ideas and drafts.
- **On x.com.** The [browser extension](extension/README.md) rings avatars by follow relationship, puts what Xtend knows beside names and on profiles, and shows your last exchange above the reply box.

## Where the data comes from

Most of it is free:

- **Your X archive.** One upload brings every post and reply you've written, the people you replied to, and your one-to-one DM metadata (who and when, never text).
- **The browser extension** copies what x.com already loaded while you browse: timelines, profiles, follow lists, notifications, and your X analytics. It makes no requests to X.
- **The X API**, optionally, one page per button press within a monthly allowance you set. Nothing runs on a schedule.

Every page says how complete its data is. See [data](docs/data.md).

## Get it running

1. [Request your X archive](docs/setup.md#1-request-your-x-archive) now; X takes a day or two.
2. [Create an X developer app](docs/setup.md#2-create-an-x-developer-app) with read-only access and your callback URL.
3. Run it locally, or [deploy it](docs/deploy.md) with Kamal or Docker Compose.
4. Allow your X account, sign in, and follow **Get started**, which ticks each step as Xtend sees it done.

### Run it locally

You need Ruby 4.0.2 and Bundler. [Parcela](https://github.com/lostcoords/parcela) gives you `https://xtend.localhost` with a trusted certificate; any HTTPS setup works.

```sh
git clone https://github.com/davafons/xtend.git && cd xtend
bundle install
export X_CLIENT_ID=... X_CLIENT_SECRET=... X_REDIRECT_URI=https://xtend.localhost/x/connection/callback
bin/dev --detach            # with Parcela; `parcela url web` prints the address
bin/rails users:allow HANDLE=yourhandle
```

With Parcela, run `users:allow` with the environment's data directory: `PARCELA_DATA_DIR=~/.local/state/parcela/environments/<id>/data`, from `parcela ls`.

To look around without X, seed the isolated demo, which uses its own database and a banner, then start the web process with `XTEND_DEMO=1`:

```sh
XTEND_DEMO=1 bin/rails db:prepare demo:seed
```

## Connect an AI

Xtend is an MCP server at `/mcp`, with its own OAuth sign-in, so any MCP client can connect: Claude, ChatGPT, Grok, or your editor's agent.

```sh
claude mcp add --transport http xtend https://xtend.example.com/mcp
```

The AI reads your people, replies, network, and analytics, and runs Xtend's tasks: `tag_people`, `review_follows`, `research_person`, `weekly_review`, `what_works`, `post_ideas`, and `find_reply_targets`. It writes only to Xtend's own records, each change can be undone, and it never posts, follows, or messages on X. See [Connect an AI](docs/ai.md).

## Develop

```sh
bin/rails test
bin/rails zeitwerk:check
```

Tests cover the domain rules: reply direction, distinct outreach targets, duplicate ingestion, automatic person records, manual choices surviving sync, and cleanup exclusions. [AGENTS.md](AGENTS.md) has the conventions, for people and coding agents alike. The UI uses the [lostcoords-ui](https://github.com/lostcoords/ui) components, and in development, [Tensaku](https://github.com/lostcoords/tensaku) lets you edit page text in place.

## License

Xtend is licensed under the [MIT License](LICENSE).
