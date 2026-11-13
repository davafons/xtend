// Runs in x.com's own page context. It copies responses the web app already received for a short list of
// operations and hands them to bridge.js: GraphQL reads, your own likes, reposts, bookmarks, and posts, and your
// follow and unfollow clicks. It never starts a request, changes a request, or reads DMs.
//
// With the raw debug log turned on (popup), it also copies every other JSON response from X's API, so new
// payloads can be studied before Xtend parses them. DMs, sign-in, and telemetry are never copied.
(() => {
  const OPERATIONS = new Set([
    "HomeTimeline", "HomeLatestTimeline", "SearchTimeline", "UserTweets", "UserOriginalsTimeline", "UserTweetsAndReplies",
    "UserRepliesTimeline", "UserRepostsTimeline", "UserVideoTimeline",
    "TweetDetail", "TweetResultByRestId", "Likes", "Bookmarks", "UserByScreenName", "UserByRestId",
    "Followers", "Following", "BlueVerifiedFollowers", "FollowersYouKnow", "ListLatestTweetsTimeline", "UserMedia",
    "Favoriters", "Retweeters", "NotificationsTimeline", "UsersByRestIds",
    "CreateTweet", "CreateNoteTweet", "FavoriteTweet", "CreateRetweet", "CreateBookmark",
    // Your own analytics pages: Overview (per day), Content (per post and reply), and Audience (hourly, who saw you).
    "accountOverviewDailyQuery", "contentPageQuery", "audienceOverviewDataQuery",
  ]);
  const GRAPHQL = /\/i\/api\/graphql\/[^/]+\/([A-Za-z]+)/;
  // Following and unfollowing are REST calls with a form body naming the account.
  const FRIENDSHIPS = /\/i\/api\/1\.1\/friendships\/(create|destroy)\.json/;
  const FRIENDSHIP_OPERATIONS = { create: "FollowCreate", destroy: "FollowDestroy" };
  // A profile hover card's "Followed by" line: accounts you follow who follow `user_id`.
  const FOLLOWING_FOLLOWERS = /\/i\/api\/1\.1\/friends\/following\/list\.json/;
  // What the raw log may copy: X's API on x.com or api.x.com, minus private messages, sign-in, and telemetry.
  const API = /^https:\/\/(x\.com\/i\/api|api\.x\.com)\//;
  const NEVER_RAW = /\/dm\/|DirectMessage|\/DM[A-Z]|xchat|keyregistry|keystore|onboarding|\/sso|login|password|oauth|guest|account\/|jot|client_event|live_pipeline|\/promoted/i;
  const RAW_QUEUE_LIMIT = 200;
  const requests = new WeakMap();
  // Unknown until bridge.js reads the setting; responses seen before then wait in a short queue.
  let raw = null;
  let rawQueue = [];

  window.addEventListener("message", (event) => {
    if (event.source !== window || event.origin !== location.origin) return;
    if (event.data?.source !== "xtend-config") return;
    raw = event.data.raw === true;
    const queued = rawQueue;
    rawQueue = [];
    if (raw) queued.forEach((entry) => entry.read().then((text) => forwardRaw(entry, text)).catch(() => {}));
  });

  const operationOf = (url) => {
    const friendship = FRIENDSHIPS.exec(url);
    if (friendship) return FRIENDSHIP_OPERATIONS[friendship[1]];
    if (FOLLOWING_FOLLOWERS.test(url)) return "FollowingFollowers";
    const match = GRAPHQL.exec(url);
    return match && OPERATIONS.has(match[1]) ? match[1] : null;
  };

  const absolute = (url) => {
    try { return new URL(url, location.origin).href; } catch { return ""; }
  };
  const rawCandidate = (url) => {
    const href = absolute(url);
    return API.test(href) && !NEVER_RAW.test(href);
  };

  const variablesOf = (url, body) => {
    try {
      if (FRIENDSHIPS.test(url)) {
        const form = new URLSearchParams(body instanceof URLSearchParams ? body : typeof body === "string" ? body : "");
        return form.get("user_id") ? { user_id: form.get("user_id") } : {};
      }
      if (FOLLOWING_FOLLOWERS.test(url)) {
        const user = new URL(url, location.origin).searchParams.get("user_id");
        return user ? { userId: user } : {};
      }
      const query = new URL(url, location.origin).searchParams.get("variables");
      if (query) return JSON.parse(query);
      if (typeof body === "string") return JSON.parse(body).variables || {};
    } catch {}
    return {};
  };

  // The address without the GraphQL feature flags, which are long and the same on every call.
  const rawUrl = (url) => {
    try {
      const parsed = new URL(url, location.origin);
      parsed.searchParams.delete("features");
      parsed.searchParams.delete("fieldToggles");
      return parsed.href;
    } catch {
      return String(url);
    }
  };

  const forward = (operation, url, requestBody, text) => {
    if (typeof text !== "string" || text.length === 0) return;
    window.postMessage(
      { source: "xtend-capture", operation, variables: variablesOf(url, requestBody), body: text, at: Date.now() },
      location.origin,
    );
  };

  function forwardRaw(entry, text) {
    if (typeof text !== "string" || text.length === 0) return;
    window.postMessage({
      source: "xtend-raw", method: entry.method, url: rawUrl(entry.url), status: entry.status,
      operation: GRAPHQL.exec(entry.url)?.[1] || null, variables: variablesOf(entry.url, entry.body),
      contentType: entry.contentType, body: text, at: entry.at,
    }, location.origin);
  }

  // Only JSON answers are worth keeping; images, scripts, and empty bodies are skipped.
  const handleRaw = (entry) => {
    if (raw === false || !/json/i.test(entry.contentType || "")) return;
    if (raw === null) {
      if (rawQueue.length < RAW_QUEUE_LIMIT) rawQueue.push(entry);
      return;
    }
    entry.read().then((text) => forwardRaw(entry, text)).catch(() => {});
  };

  const open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    const text = String(url);
    const operation = operationOf(text);
    const candidate = rawCandidate(text);
    if (operation || candidate) requests.set(this, { operation, raw: candidate, method: String(method).toUpperCase(), url: text });
    return open.call(this, method, url, ...rest);
  };

  const send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function (body) {
    const request = requests.get(this);
    if (request) {
      this.addEventListener("load", () => {
        const text = () => this.responseType === "json" ? JSON.stringify(this.response)
          : this.responseType === "" || this.responseType === "text" ? this.responseText : null;
        const wanted = (request.operation && this.status === 200) || (request.raw && raw !== false);
        const value = wanted ? text() : null;
        if (request.operation && this.status === 200) forward(request.operation, request.url, body, value);
        if (request.raw && raw !== false) {
          handleRaw({ ...request, body, status: this.status, contentType: this.getResponseHeader("content-type"),
            at: Date.now(), read: () => Promise.resolve(value) });
        }
      });
    }
    return send.call(this, body);
  };

  const originalFetch = window.fetch;
  window.fetch = async function (input, init) {
    const response = await originalFetch.apply(this, arguments);
    try {
      const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
      const operation = operationOf(url);
      if (operation && response.ok) {
        response.clone().text().then((text) => forward(operation, url, init && init.body, text)).catch(() => {});
      }
      if (raw !== false && rawCandidate(url)) {
        const copy = response.clone();
        handleRaw({ method: String(init?.method || input?.method || "GET").toUpperCase(), url, body: init && init.body,
          status: response.status, contentType: response.headers.get("content-type"), at: Date.now(), read: () => copy.text() });
      }
    } catch {}
    return response;
  };
})();
