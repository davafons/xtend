# Xtend Capture

A Brave/Chrome extension that forwards what x.com already loaded while you browse to Xtend, and shows what Xtend knows about the people on screen.

## What Xtend knows, on x.com

- **A ring around every avatar.** In the follow relationship's color, as in Xtend: green for mutuals, blue for people you follow, amber for people who follow you, and dashed grey for neither. Someone Xtend has no person for counts as neither only when both follow lists are complete, dated by the older check; otherwise there is no ring. Hover the avatar for the state. Your own avatar has none.
- **Badges by names.** After the handle on posts and in user lists: whether you're mutuals, you follow them, or they follow you; replies from you and from them; how long since the last reply; a pin; and a bell when a reminder is due. Hover the badge for the latest interaction, tags, and notes. People Xtend has nothing on get no badge.
- **A line in X's hover card.** The same facts plus tags, a line of your notes, and an open reminder.
- **A card on profiles.** At the top of the sidebar, under X's search: relationship, pinned and kept marks, replies both ways, last reply, latest interaction, tags, your notes, your reminder, and a link to the person in Xtend. A profile Xtend doesn't know yet is sent to Xtend right away and the card fills in a moment later. The latest interaction links to that kind's history on the person's page in Xtend, which lists every reply, like, bookmark, DM, and follow change with the posts themselves.

The extension asks Xtend (`GET /x/captures/context?handles=…`, read-only, with the same link that sends captures) only for handles x.com is already showing, keeps answers for three minutes, and asks again after each batch it sends. Everything it adds sits in closed shadow roots that x.com's scripts can't read, but notes and tags are on screen, so mind screen sharing. Turn it off in the popup with **Show what Xtend knows on x.com**.

- **No requests to X.** It copies responses the web app received for timelines, lists, search, profiles (every tab), threads, likes, bookmarks, notifications, follow lists ("Followers", "Following", "Followers you know", and the "Followed by" line on profile hover cards), and "Liked by" / "Reposted by" lists. It also copies the answers to your own actions: follow and unfollow clicks, likes, reposts, bookmarks, and new posts or replies. It never starts, changes, or repeats a request, and never reads DMs.
- **What Xtend keeps.** Every account it sees goes in a directory; only people you showed interest in (visited profiles, likes, bookmarks, reply exchanges) become people. Posts you were shown and posts touching your people are saved with their counts at each sighting, and replies, quotes, reposts, mentions, likes, and follow edges feed the Network page.
- **Your notifications.** Scrolling `x.com/notifications` saves replies and mentions as posts, records who liked or reposted your posts (grouped notifications list every account), and dates new followers to the minute X reports. A "liked 2 of your posts" notification names only one post, and the list only reaches as far back as you scroll.
- **Your follow state, live.** Every account x.com shows says whether you follow it and whether it follows you. The newest sighting per person corrects the last follow check, and an unfollow you make on X is recorded in Follow review on its own. Every post says whether you liked, reposted, or bookmarked it, so those count as interactions without visiting your Likes page.
- **Complete follow lists by scrolling.** Scroll your own Followers or Following page on x.com to the end and Xtend saves a complete list, the same as an X API check, for free. Each page has to continue where the previous one ended, and the total has to match your profile's count, so a skipped page leaves the list unfinished and nothing changes. A complete follower list dates who started or stopped following you since the last one.
- **Otherwise only what you saw.** Everything else covers only what you scrolled past. Xtend never treats it as a complete like history or as proof something didn't happen.
- **Only your account.** Xtend refuses batches when the browser is signed in to a different X account than the workspace.

## Raw debug log

To study a payload Xtend doesn't parse yet, turn on **Raw debug log** in the popup and browse. Every JSON response from X's API (`x.com/i/api/…` and `api.x.com`) is kept in extension storage with its method, URL (without the long `features` flags), status, GraphQL operation and variables, the x.com page it was loaded on, and the body as received. DMs, sign-in, onboarding, and telemetry are never logged. The log holds the newest 5,000 responses or 100 MB, is never sent to Xtend, and leaves the browser only when you choose **Download log** (a `.jsonl` file, one response per line). Turn it off and clear it when you are done.

## Install

1. Open `brave://extensions`, turn on **Developer mode**, choose **Load unpacked**, and select this `extension` folder.
2. In the extension's options, check the Xtend address (default `https://xtend.example.com`; use `https://xtend.localhost` for local development) and choose **Connect to Xtend**. Xtend opens in a window for you to approve, then the extension tests the connection.
3. To disconnect, use **Disconnect** in the options, or disconnect the extension in Xtend under **X data → Browser extension**.

The extension links with OAuth (authorization code with PKCE through `chrome.identity`), so it holds a capture-only token that renews itself and works nowhere else. A pasted capture token still works for a setup by hand: create one in Xtend and paste it under **Use a pasted token instead**. `/x/captures`, `/oauth/token`, and `/oauth/revoke` bypass Cloudflare Access; the approval page doesn't.

Browse x.com as usual. The toolbar badge counts pages waiting to be sent. The popup has **Send to Xtend**, an automatic one-minute send toggle, and **Pause capture**. Captures queue in extension storage while Xtend is unreachable.

## How it works

`overlay.js` runs in the extension's isolated world on x.com, finds handles in posts, user lists, hover cards, and the profile header, asks `background.js` for their context, and renders badges and cards. `page.js` runs in x.com's page context and observes XHR and fetch responses for an allowlist of GraphQL operations. `bridge.js` relays them to `background.js`, which queues them and posts batches to `POST /x/captures` with its access token, renewing it with the refresh token first when it is a day from expiring or was refused. Xtend parses them in `X::WebPayload` and saves them through `X::Capture`.

X changes its web app's GraphQL shapes without notice. When a capture stops adding data, compare a fresh response with `X::WebPayload`.

Capturing data from x.com this way may conflict with X's terms of service. Use it for your own account at normal browsing speed.
