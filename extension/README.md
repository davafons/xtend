# Twitter CRM Capture

A Brave/Chrome extension that forwards what x.com already loaded while you browse to your Twitter CRM.

- **No requests to X.** It copies GraphQL responses the web app received for timelines, search, profiles, threads, likes, bookmarks, and follow lists. It never starts, changes, or repeats a request, and never reads DMs.
- **Only what you saw.** Coverage is limited to what you scrolled past. The CRM never treats a capture as a complete follower list or like history.
- **Only your account.** The CRM refuses batches when the browser is signed in to a different X account than the workspace.

## Install

1. In the CRM, open **X data → Browser capture** and create a capture token.
2. Open `brave://extensions`, turn on **Developer mode**, choose **Load unpacked**, and select this `extension` folder.
3. In the extension's options, enter the CRM address (default `https://twitter-crm.localhost`) and the token, then **Save and test**.

Browse x.com as usual. The toolbar badge counts pages waiting to be sent. The popup has **Send to CRM**, an automatic one-minute send toggle, and **Pause capture**. Captures queue in extension storage while the CRM is unreachable.

## How it works

`page.js` runs in x.com's page context and observes XHR and fetch responses for an allowlist of GraphQL operations. `bridge.js` relays them to `background.js`, which queues them and posts batches to `POST /x/captures` with the capture token. The CRM parses them in `X::WebPayload` and saves them through `X::Capture`.

X changes its web app's GraphQL shapes without notice. When a capture stops adding data, compare a fresh response with `X::WebPayload`.

Capturing data from x.com this way may conflict with X's terms of service. Use it for your own account at normal browsing speed.
