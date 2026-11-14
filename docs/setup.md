# Set up Xtend

Xtend runs on your own machine or server and reads X with your own X developer app. Setup takes about half an hour, plus a day or two of waiting for X to prepare your archive, so request that first.

1. [Request your X archive](#1-request-your-x-archive) (it takes X a day or more)
2. [Create an X developer app](#2-create-an-x-developer-app)
3. [Run or deploy Xtend](#3-run-or-deploy-xtend)
4. [Allow your account and sign in](#4-allow-your-account-and-sign-in)
5. [Follow the Get started page](#5-follow-the-get-started-page)

## 1. Request your X archive

On x.com, open **Settings → Your account → Download an archive of your data**, confirm your password, and request it. X emails you when the `.zip` is ready, usually within a day or two.

The archive is the fastest way to fill Xtend: every post and reply you've written becomes people and reply history, and your one-to-one DMs add who and when (never the text). Xtend reads it locally; it makes no API calls.

## 2. Create an X developer app

Xtend signs you in with X and reads your account with the X API, using an app you own.

1. Open the [X developer console](https://console.x.com) and sign in with the account you'll use Xtend with.
2. Create an app.
3. Under **User authentication settings**, choose **Set up** and pick:
   - **App permissions:** Read.
   - **Type of app:** Web App, Automated App or Bot (a confidential client, with a client secret).
   - **Callback URI:** `https://YOUR-XTEND-HOST/x/connection/callback`, exactly. For local development that's `https://xtend.localhost/x/connection/callback`. You can list both.
   - **Website URL:** your Xtend address, or any page you own.
4. Save, then copy the **OAuth 2.0 Client ID** and **Client Secret** from **Keys and tokens**. Treat the secret like a password.

Xtend asks for these read-only scopes: `tweet.read users.read follows.read like.read bookmark.read dm.read offline.access`. It never asks to post, follow, or send messages.

### Billing

The X API is pay per use: you buy credits in the console, and each resource a request returns costs a little. Signing in reads your profile once (about $0.01). Everything else is optional and starts only when you press a button in Xtend, one page at a time: a full follower and following check costs about $0.001 per account at the rate for apps you own. A few dollars of credit goes a long way.

Set a spending cap in the console, and set the same amount as your monthly allowance on Xtend's **Spending** page, which refuses reads that would go over it. The console's numbers are the real bill; Xtend's are estimates. `scripts/estimate-x-costs.py` estimates a month for your account size.

You can use Xtend without buying API reads beyond sign-in: the archive and the browser extension fill most of it for free.

## 3. Run or deploy Xtend

Xtend reads its settings from the environment:

| Variable | What it is |
| --- | --- |
| `X_CLIENT_ID`, `X_CLIENT_SECRET` | From your X app. |
| `X_REDIRECT_URI` | The callback URI you registered, such as `https://xtend.example.com/x/connection/callback`. |
| `APP_HOSTS` | Your public hostname, in production. |
| `SECRET_KEY_BASE` | A long random secret, from `bin/rails secret`, in production. |
| `APP_DATA_DIR` | Where SQLite and the X token key live. The Docker image uses `/data`. |

To try it on your computer, see [Run it locally](../README.md#run-it-locally). To put it on a server, see [Deploy](deploy.md). Locally you can also put the X settings in Rails credentials under `x:` (`client_id`, `client_secret`, `redirect_uri`).

## 4. Allow your account and sign in

There's no signup. Allow your X handle once:

```sh
bin/rails users:allow HANDLE=yourhandle
```

On a Kamal deploy that's `bin/kamal allow HANDLE=yourhandle`; with Docker Compose, `docker compose exec xtend bin/rails users:allow HANDLE=yourhandle`.

Open Xtend and choose **Sign in with X**. The account is pinned to its X user ID on first sign-in, so a renamed handle keeps working and nobody else can take it. `users:list` shows allowed accounts and `users:revoke HANDLE=...` removes one.

## 5. Follow the Get started page

After you sign in, **Get started** walks through the rest and ticks each step as Xtend sees it done:

- **Import your X archive** on the X data page.
- **Install the browser extension** and connect it. It copies what x.com already loads while you browse and shows what Xtend knows about people beside their names. See [the extension](../extension/README.md).
- **Complete your follow lists** by scrolling your own Followers and Following pages on x.com to the end, with the extension on. That's a free, complete follow check.
- **Open X Analytics** on x.com once, so Xtend has your impressions, profile visits, and busy hours.
- **Connect an AI** if you want one to tag people, review follows, and write your weekly review. See [AI connector](ai.md).
- **Start a growth plan** with a follower goal and weekly checkpoints.

Each step is optional, and every page says how complete its data is.
