# Twitter CRM Capture

A Brave/Chrome extension that forwards what x.com already loaded while you browse to your Twitter CRM.

- **No requests to X.** It copies responses the web app received for timelines, lists, search, profiles, threads, likes, bookmarks, follow lists ("Followers", "Following", "Followers you know"), and "Liked by" / "Reposted by" lists. It also copies the answers to your own actions: follow and unfollow clicks, likes, reposts, bookmarks, and new posts or replies. It never starts, changes, or repeats a request, and never reads DMs.
- **What the CRM keeps.** Every account it sees goes in a directory; only people you showed interest in (visited profiles, likes, bookmarks, reply exchanges) become people. Posts you were shown and posts touching your people are saved with their counts at each sighting, and replies, quotes, reposts, mentions, likes, and follow edges feed the Network page.
- **Your follow state, live.** Every account x.com shows says whether you follow it and whether it follows you. The newest sighting per person corrects the last follow check, and an unfollow you make on X is recorded in Follow review on its own. Every post says whether you liked, reposted, or bookmarked it, so those count as interactions without visiting your Likes page.
- **Complete follow lists by scrolling.** Scroll your own Followers or Following page on x.com to the end and the CRM saves a complete list, the same as an X API check, for free. Each page has to continue where the previous one ended, and the total has to match your profile's count, so a skipped page leaves the list unfinished and nothing changes. A complete follower list dates who started or stopped following you since the last one.
- **Otherwise only what you saw.** Everything else covers only what you scrolled past. The CRM never treats it as a complete like history or as proof something didn't happen.
- **Only your account.** The CRM refuses batches when the browser is signed in to a different X account than the workspace.

## Install

1. In the CRM, open **X data → Browser capture** and create a capture token.
2. Open `brave://extensions`, turn on **Developer mode**, choose **Load unpacked**, and select this `extension` folder.
3. In the extension's options, enter the CRM address (default `https://xtend.example.com`; use `https://twitter-crm.localhost` for local development) and the token, then **Save and test**. `/x/captures` bypasses Cloudflare Access and is authenticated by the token.

Browse x.com as usual. The toolbar badge counts pages waiting to be sent. The popup has **Send to CRM**, an automatic one-minute send toggle, and **Pause capture**. Captures queue in extension storage while the CRM is unreachable.

## How it works

`page.js` runs in x.com's page context and observes XHR and fetch responses for an allowlist of GraphQL operations. `bridge.js` relays them to `background.js`, which queues them and posts batches to `POST /x/captures` with the capture token. The CRM parses them in `X::WebPayload` and saves them through `X::Capture`.

X changes its web app's GraphQL shapes without notice. When a capture stops adding data, compare a fresh response with `X::WebPayload`.

Capturing data from x.com this way may conflict with X's terms of service. Use it for your own account at normal browsing speed.
