const $ = (id) => document.getElementById(id);
const send = (type) => chrome.runtime.sendMessage({ type });

const LABELS = {
  HomeTimeline: "Home", HomeLatestTimeline: "Home (latest)", SearchTimeline: "Search", UserTweets: "Profiles", UserOriginalsTimeline: "Profiles",
  UserTweetsAndReplies: "Profile replies", TweetDetail: "Threads", TweetResultByRestId: "Posts", Likes: "Likes",
  Bookmarks: "Bookmarks", UserByScreenName: "Profile headers", UserByRestId: "Profile headers",
  Followers: "Followers", Following: "Following", BlueVerifiedFollowers: "Followers",
  UserRepliesTimeline: "Profile replies", UserRepostsTimeline: "Profile reposts", UserVideoTimeline: "Profiles",
  NotificationsTimeline: "Notifications", UsersByRestIds: "Profiles", FollowingFollowers: "Followed by",
};

function render({ settings, state, raw }) {
  $("rawDebug").checked = settings.rawDebug;
  $("rawCount").textContent = raw.count
    ? `${raw.count} response${raw.count === 1 ? "" : "s"} logged · ${(raw.bytes / 1024 / 1024).toFixed(1)} MB`
    : settings.rawDebug ? "Logging. Browse x.com, then download." : "Off.";
  $("rawDownload").disabled = !raw.count;
  $("rawClear").disabled = !raw.count;
  $("badge").textContent = !settings.token ? "Not set up" : settings.paused ? "Paused" : "Capturing";
  $("pending").textContent = `${state.pending} page${state.pending === 1 ? "" : "s"} waiting`;
  const counts = {};
  for (const [operation, count] of Object.entries(state.byOperation)) {
    if (count) counts[LABELS[operation] || operation] = (counts[LABELS[operation] || operation] || 0) + count;
  }
  $("operations").replaceChildren(...Object.entries(counts).map(([label, count]) => {
    const item = document.createElement("li");
    item.textContent = `${label}: ${count}`;
    return item;
  }));
  $("error").hidden = !state.lastError;
  $("error").textContent = state.lastError || "";
  const result = state.lastResult;
  $("last").textContent = state.lastSentAt
    ? `Last sent ${new Date(state.lastSentAt).toLocaleTimeString()}` +
      (result && result.posts !== undefined ? `: ${result.posts} posts, ${result.interactions || 0} interactions, ${result.follows || 0} follow edges, ${result.people_added} new people` : "") +
      ((result && result.lists || []).map((list) => ` · ${list.direction} list ${list.state === "completed" ? "complete" : "so far"}: ${list.seen}${list.expected ? ` of ${list.expected}` : ""}`).join(""))
    : "Nothing sent yet.";
  const totals = state.totals;
  $("totals").textContent = totals.posts || totals.people_added
    ? `Since install: ${totals.posts || 0} posts · ${totals.interactions || 0} interactions · ${totals.relationships || 0} follow states · ${totals.unfollows || 0} unfollows · ${totals.notifications || 0} notifications · ${totals.people_added || 0} new people`
    : "";
  $("auto").checked = settings.auto;
  $("paused").checked = settings.paused;
  $("send").disabled = !state.pending || !settings.token;
}

const refresh = async () => render(await send("status"));

async function saveSetting(field, value) {
  const { settings } = await chrome.storage.local.get("settings");
  await chrome.storage.local.set({ settings: { ...settings, [field]: value } });
  refresh();
}

$("send").addEventListener("click", async () => {
  $("send").disabled = true;
  $("send").textContent = "Sending…";
  await send("flush");
  $("send").textContent = "Send to CRM";
  refresh();
});
$("clear").addEventListener("click", async () => { await send("clear"); refresh(); });
$("auto").addEventListener("change", (event) => saveSetting("auto", event.target.checked));
$("paused").addEventListener("change", (event) => saveSetting("paused", event.target.checked));
$("rawDebug").addEventListener("change", (event) => saveSetting("rawDebug", event.target.checked));
$("rawClear").addEventListener("click", async () => { await send("clear-raw"); refresh(); });
// One JSON object per line: method, url, status, operation, variables, page, at, and the response body as text.
$("rawDownload").addEventListener("click", async () => {
  const keys = (await chrome.storage.local.getKeys()).filter((key) => key.startsWith("raw:")).sort();
  const lines = [];
  for (let i = 0; i < keys.length; i += 200) {
    const items = await chrome.storage.local.get(keys.slice(i, i + 200));
    for (const key of keys.slice(i, i + 200)) if (items[key]) lines.push(JSON.stringify(items[key]));
  }
  const link = document.createElement("a");
  link.href = URL.createObjectURL(new Blob([lines.join("\n") + "\n"], { type: "application/x-ndjson" }));
  link.download = `twitter-crm-raw-${new Date().toISOString().replace(/[:.]/g, "-")}.jsonl`;
  link.click();
  setTimeout(() => URL.revokeObjectURL(link.href), 60000);
});
chrome.storage.onChanged.addListener(refresh);
refresh();
