// Runs in x.com's own page context. It copies responses the web app already received for a short list of
// operations and hands them to bridge.js: GraphQL reads, your own likes, reposts, bookmarks, and posts, and your
// follow and unfollow clicks. It never starts a request, changes a request, or reads DMs.
(() => {
  const OPERATIONS = new Set([
    "HomeTimeline", "HomeLatestTimeline", "SearchTimeline", "UserTweets", "UserOriginalsTimeline", "UserTweetsAndReplies",
    "TweetDetail", "TweetResultByRestId", "Likes", "Bookmarks", "UserByScreenName", "UserByRestId",
    "Followers", "Following", "BlueVerifiedFollowers", "FollowersYouKnow", "ListLatestTweetsTimeline", "UserMedia",
    "Favoriters", "Retweeters",
    "CreateTweet", "CreateNoteTweet", "FavoriteTweet", "CreateRetweet", "CreateBookmark",
  ]);
  const GRAPHQL = /\/i\/api\/graphql\/[^/]+\/([A-Za-z]+)/;
  // Following and unfollowing are REST calls with a form body naming the account.
  const FRIENDSHIPS = /\/i\/api\/1\.1\/friendships\/(create|destroy)\.json/;
  const FRIENDSHIP_OPERATIONS = { create: "FollowCreate", destroy: "FollowDestroy" };
  const requests = new WeakMap();

  const operationOf = (url) => {
    const friendship = FRIENDSHIPS.exec(url);
    if (friendship) return FRIENDSHIP_OPERATIONS[friendship[1]];
    const match = GRAPHQL.exec(url);
    return match && OPERATIONS.has(match[1]) ? match[1] : null;
  };

  const variablesOf = (url, body) => {
    try {
      if (FRIENDSHIPS.test(url)) {
        const form = new URLSearchParams(body instanceof URLSearchParams ? body : typeof body === "string" ? body : "");
        return form.get("user_id") ? { user_id: form.get("user_id") } : {};
      }
      const query = new URL(url, location.origin).searchParams.get("variables");
      if (query) return JSON.parse(query);
      if (typeof body === "string") return JSON.parse(body).variables || {};
    } catch {}
    return {};
  };

  const forward = (operation, url, requestBody, text) => {
    if (typeof text !== "string" || text.length === 0) return;
    window.postMessage(
      { source: "twitter-crm-capture", operation, variables: variablesOf(url, requestBody), body: text, at: Date.now() },
      location.origin,
    );
  };

  const open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    const operation = operationOf(String(url));
    if (operation) requests.set(this, { operation, url: String(url) });
    return open.call(this, method, url, ...rest);
  };

  const send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function (body) {
    const request = requests.get(this);
    if (request) {
      this.addEventListener("load", () => {
        if (this.status !== 200) return;
        const text = this.responseType === "json" ? JSON.stringify(this.response)
          : this.responseType === "" || this.responseType === "text" ? this.responseText : null;
        forward(request.operation, request.url, body, text);
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
    } catch {}
    return response;
  };
})();
