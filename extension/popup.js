const $ = (id) => document.getElementById(id);
const send = (type) => chrome.runtime.sendMessage({ type });

const LABELS = {
  HomeTimeline: "Home", HomeLatestTimeline: "Home (latest)", SearchTimeline: "Search", UserTweets: "Profiles", UserOriginalsTimeline: "Profiles",
  UserTweetsAndReplies: "Profile replies", TweetDetail: "Threads", TweetResultByRestId: "Posts", Likes: "Likes",
  Bookmarks: "Bookmarks", UserByScreenName: "Profile headers", UserByRestId: "Profile headers",
  Followers: "Followers", Following: "Following", BlueVerifiedFollowers: "Followers",
};

function render({ settings, state }) {
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
    ? `Since install: ${totals.posts || 0} posts · ${totals.interactions || 0} interactions · ${totals.relationships || 0} follow states · ${totals.unfollows || 0} unfollows · ${totals.people_added || 0} new people`
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
chrome.storage.onChanged.addListener(refresh);
refresh();
