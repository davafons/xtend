# Connect an AI

Xtend is an [MCP](https://modelcontextprotocol.io) server at `/mcp`. Any MCP client that supports remote servers over HTTP with OAuth can connect: Claude, ChatGPT, Grok, Cursor, or a coding agent. The AI reads what Xtend knows and writes to Xtend's own records. It never acts on X.

## Connect

Add `https://YOUR-XTEND-HOST/mcp` as a remote MCP server in your client. The client registers itself, opens Xtend in your browser, and you approve it. For example, in Claude Code:

```sh
claude mcp add --transport http xtend https://xtend.example.com/mcp
```

Then run `/mcp` and authenticate. Clients that can't do OAuth can use a token you paste: create one on Xtend's **AI** page.

Xtend's own OAuth server handles this (discovery at `/.well-known/oauth-authorization-server`, dynamic client registration, PKCE, and rotating refresh tokens). Tokens are scoped to MCP only, and you can revoke each client on the **AI** page.

## What it can do

**Tasks.** Each task is an MCP prompt, and also available through the `get_task` tool for clients without prompt support. Ask your AI to "Run the Xtend task weekly_review", or pick it from the client's prompt menu.

| Task | What it does |
| --- | --- |
| `tag_people` | Tags people by topic from their bios and posts. |
| `review_follows` | Goes through follow cleanup candidates and explains which to keep. |
| `research_person` | Writes a recap of one person and fills empty profile facts. |
| `weekly_review` | Reviews your week against the one before and your growth plan, and sets reminders. |
| `what_works` | Compares your replies and posts by account size, timing, and format. |
| `post_ideas` | Saves post ideas from what works and what your network is talking about. |
| `find_reply_targets` | Finds fresh posts worth replying to and adds them to Outreach, unverified. |

**Reading.** Your profile and interests, people with their follow state and history, interactions, network posts, the follow graph, X analytics, the week in review, the growth plan, and post drafts. Notes and DM metadata are shared only if you turn them on under **AI → What assistants can see**.

**Writing.** Tags, notes, reminders, recaps, profile facts, post ideas and drafts, and unverified reply targets. Every change is logged with what it did:

- With **AI applies changes** on (the default), changes apply at once and each one has **Undo** on the AI page and the person's page. Undo reverses exactly that change and leaves anything you changed since.
- With it off, changes wait for you to accept or dismiss them.

An AI never removes or edits your own tags or notes, never fills a profile field you already set, and has no tool to post, reply, like, follow, unfollow, or message on X. Nothing runs on a schedule: the AI works only when you ask it to.
