// Runs in x.com's own page context. It copies GraphQL responses the web app already received for a short list of
// operations and hands them to bridge.js. It never starts a request, changes a request, or reads DMs.
(() => {
  const OPERATIONS = new Set([
    "HomeTimeline", "HomeLatestTimeline", "SearchTimeline", "UserTweets", "UserOriginalsTimeline", "UserTweetsAndReplies",
    "TweetDetail", "TweetResultByRestId", "Likes", "Bookmarks", "UserByScreenName", "UserByRestId",
    "Followers", "Following", "BlueVerifiedFollowers",
  ]);
  const GRAPHQL = /\/i\/api\/graphql\/[^/]+\/([A-Za-z]+)/;
  const requests = new WeakMap();

  const operationOf = (url) => {
    const match = GRAPHQL.exec(url);
    return match && OPERATIONS.has(match[1]) ? match[1] : null;
  };

  const variablesOf = (url, body) => {
    try {
      const query = new URL(url, location.origin).searchParams.get("variables");
      if (query) return JSON.parse(query);
      if (typeof body === "string") return JSON.parse(body).variables || {};
    } catch {}
    return {};
  };

  const forward = (operation, url, requestBody, text) => {
    if (typeof text !== "string" || text.length === 0) return;
    window.postMessage(
      { source: "twitter-crm-capture", operation, variables: variablesOf(url, requestBody), body: text },
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
