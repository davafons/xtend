// Queues captured responses in extension storage and sends them to Xtend in batches: a few seconds after you stop
// scrolling, on demand, or every minute as a fallback. After each batch it tells open Xtend tabs to refresh and shows
// follow-list progress on x.com.
import { needsRenewal, refresh } from "./oauth.js";

// token is an OAuth access token (renewed with refreshToken) or a pasted capture token (no refreshToken).
const DEFAULT_SETTINGS = { xtendUrl: "https://xtend.example.com", token: "", refreshToken: "", expiresAt: null, auto: true, paused: false, rawDebug: false, overlay: true };
// The raw debug log stays in extension storage until you download it from the popup; it is never sent anywhere.
const RAW_PREFIX = "raw:";
const MAX_RAW_ENTRIES = 5000;
const MAX_RAW_BYTES = 100 * 1024 * 1024;
const MAX_QUEUE = 2000;
const MAX_BATCH_RESPONSES = 50;
const MAX_BATCH_BYTES = 6 * 1024 * 1024;
const ITEM_PREFIX = "q:";
const SEND_DELAY_MS = 4000;
const XTEND_TABS = ["https://xtend.example.com/*", "https://xtend.localhost/*"];
// What Xtend knows about the people on screen, kept briefly so scrolling a timeline doesn't ask twice.
const CONTEXT_TTL_MS = 3 * 60 * 1000;
const CONTEXT_MAX_HANDLES = 100;
// Long enough for x.com's profile responses to reach the queue.
const SAVE_NOW_DELAY_MS = 1500;
const contextCache = new Map();
let sendTimer = null;

// Storage updates run one at a time so concurrent captures can't overwrite each other's counters.
let chain = Promise.resolve();
const serial = (task) => (chain = chain.then(task, task));

async function settings() {
  const { settings } = await chrome.storage.local.get("settings");
  return { ...DEFAULT_SETTINGS, ...settings };
}

async function state() {
  const { state } = await chrome.storage.local.get("state");
  return { pending: 0, byOperation: {}, totals: {}, lastSentAt: null, lastResult: null, lastError: null, ...state };
}

async function setState(changes) {
  const next = { ...(await state()), ...changes };
  await chrome.storage.local.set({ state: next });
  chrome.action.setBadgeText({ text: next.pending ? String(Math.min(next.pending, 999)) : "" });
  chrome.action.setBadgeBackgroundColor({ color: next.lastError ? "#b45309" : "#1d9bf0" });
  return next;
}

// Lists storage keys without loading every stored body.
async function keysWith(prefix) {
  const keys = chrome.storage.local.getKeys ? await chrome.storage.local.getKeys() : Object.keys(await chrome.storage.local.get(null));
  return keys.filter((key) => key.startsWith(prefix)).sort();
}

const queuedKeys = () => keysWith(ITEM_PREFIX);

function enqueue(message) {
  return serial(async () => {
    if ((await settings()).paused) return;
    const key = `${ITEM_PREFIX}${Date.now().toString().padStart(15, "0")}-${crypto.randomUUID()}`;
    await chrome.storage.local.set({ [key]: { operation: message.operation, variables: message.variables || {}, body: message.body, at: Number(message.at) || Date.now() } });
    const current = await state();
    const byOperation = { ...current.byOperation, [message.operation]: (current.byOperation[message.operation] || 0) + 1 };
    let pending = current.pending + 1;
    if (pending > MAX_QUEUE) {
      const keys = await queuedKeys();
      const dropped = keys.slice(0, pending - MAX_QUEUE);
      await chrome.storage.local.remove(dropped);
      pending -= dropped.length;
    }
    await setState({ pending, byOperation });
  }).then(async () => {
    const [{ auto }, { pending }] = await Promise.all([settings(), state()]);
    if (!auto) return;
    clearTimeout(sendTimer);
    if (pending >= MAX_BATCH_RESPONSES) flush();
    else sendTimer = setTimeout(flush, SEND_DELAY_MS);
  });
}

// What a batch means for the follow list you are scrolling, in words for the x.com toast.
function listMessages(result) {
  return (result.lists || []).map((list) => {
    const name = list.direction === "followers" ? "Followers" : "Following";
    const of = list.expected ? ` of ${list.expected}` : "";
    if (list.state === "completed") return `${name} list saved to Xtend: ${list.seen} accounts.`;
    if (list.state === "short") return `${name} list ended at ${list.seen}${of}. Some pages were missed; scroll it again from the top.`;
    return `${name} list: ${list.seen}${of} saved. Keep scrolling to the end.`;
  });
}

// x.com tabs drop what they showed and ask again, since a batch can add people, replies, and follow states.
async function staleContext() {
  contextCache.clear();
  const xTabs = await chrome.tabs.query({ url: "https://x.com/*" }).catch(() => []);
  for (const tab of xTabs) chrome.tabs.sendMessage(tab.id, { type: "context-stale" }).catch(() => {});
}

async function announce(result) {
  staleContext();
  const xtendTabs = await chrome.tabs.query({ url: XTEND_TABS }).catch(() => []);
  for (const tab of xtendTabs) chrome.tabs.sendMessage(tab.id, { type: "captured" }).catch(() => {});
  const messages = listMessages(result);
  if (result.unfollows) messages.push(`Unfollow recorded in Xtend.`);
  if (!messages.length) return;
  const xTabs = await chrome.tabs.query({ url: "https://x.com/*", active: true }).catch(() => []);
  for (const tab of xTabs) chrome.tabs.sendMessage(tab.id, { type: "toast", text: messages.join(" ") }).catch(() => {});
}

async function toastError(text) {
  const xTabs = await chrome.tabs.query({ url: "https://x.com/*", active: true }).catch(() => []);
  for (const tab of xTabs) chrome.tabs.sendMessage(tab.id, { type: "toast", text, tone: "error" }).catch(() => {});
}

async function viewerId() {
  const cookie = await chrome.cookies.get({ url: "https://x.com", name: "twid" });
  const match = cookie && decodeURIComponent(cookie.value).match(/u=(\d+)/);
  return match ? match[1] : null;
}

const origin = (xtendUrl) => xtendUrl.replace(/\/+$/, "");

// Renews the OAuth pair. A refused refresh means the link was revoked or expired, so it's dropped and the options
// page asks to connect again; a network failure keeps the old token for the next try.
let renewing = null;
function renew() {
  renewing ||= (async () => {
    const current = await settings();
    try {
      const fresh = await refresh(origin(current.xtendUrl), current.refreshToken);
      await chrome.storage.local.set({ settings: { ...current, ...fresh } });
      return fresh.token;
    } catch (error) {
      if (error.code === "invalid_grant" || error.code === "invalid_client") {
        await chrome.storage.local.set({ settings: { ...current, token: "", refreshToken: "", expiresAt: null } });
        return "";
      }
      return current.token;
    } finally {
      renewing = null;
    }
  })();
  return renewing;
}

async function accessToken() {
  const current = await settings();
  return needsRenewal(current) ? renew() : current.token;
}

async function post(batch, retry = true) {
  const { xtendUrl, refreshToken } = await settings();
  const response = await fetch(`${origin(xtendUrl)}/x/captures`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${await accessToken()}` },
    body: JSON.stringify(batch),
  });
  if (response.status === 401 && refreshToken && retry && (await renew())) return post(batch, false);
  const body = await response.json().catch(() => ({}));
  return { status: response.status, ok: response.ok, body };
}

// Reads Xtend's context for handles x.com is showing: cached answers first, the rest in one request.
async function context(handles) {
  const current = await settings();
  if (!current.overlay) return { off: true };
  if (!current.token) return { error: "not connected" };
  const now = Date.now();
  const people = {};
  const missing = [];
  for (const handle of new Set(handles.map((handle) => String(handle).toLowerCase()).filter((handle) => /^\w{1,15}$/.test(handle)))) {
    const cached = contextCache.get(handle);
    if (cached && now - cached.at < CONTEXT_TTL_MS) people[handle] = cached.person;
    else missing.push(handle);
  }
  for (let i = 0; i < missing.length; i += CONTEXT_MAX_HANDLES) {
    const chunk = missing.slice(i, i + CONTEXT_MAX_HANDLES);
    const answer = await readContext(chunk);
    if (!answer.ok) return { people, error: answer.error };
    for (const [handle, answered] of Object.entries(answer.body.people || {})) {
      const person = { ...answered, follow_checked_at: answer.body.follow_checked_at || null };
      contextCache.set(handle, { person, at: now });
      people[handle] = person;
    }
  }
  return { people };
}

async function readContext(handles, retry = true) {
  const { xtendUrl, refreshToken } = await settings();
  try {
    const response = await fetch(`${origin(xtendUrl)}/x/captures/context?handles=${encodeURIComponent(handles.join(","))}`,
      { headers: { Accept: "application/json", Authorization: `Bearer ${await accessToken()}` } });
    if (response.status === 401 && refreshToken && retry && (await renew())) return readContext(handles, false);
    const body = await response.json().catch(() => ({}));
    return response.ok ? { ok: true, body } : { ok: false, error: body.error || `Xtend answered ${response.status}.` };
  } catch {
    return { ok: false, error: "Xtend isn't reachable." };
  }
}

async function preflight() {
  const { token } = await settings();
  if (!token) return { error: "Connect to Xtend in the extension options." };
  const viewer = await viewerId();
  if (!viewer) return { error: "Sign in to x.com in this browser." };
  return { viewer };
}

function flush() {
  return serial(async () => {
    const ready = await preflight();
    if (ready.error) return setState({ lastError: ready.error });
    let keys = await queuedKeys();
    while (keys.length) {
      const items = await chrome.storage.local.get(keys.slice(0, MAX_BATCH_RESPONSES));
      const batchKeys = [];
      const responses = [];
      let bytes = 0;
      for (const key of keys.slice(0, MAX_BATCH_RESPONSES)) {
        const item = items[key];
        if (!item) continue;
        if (responses.length && bytes + item.body.length > MAX_BATCH_BYTES) break;
        batchKeys.push(key);
        responses.push(item);
        bytes += item.body.length;
      }
      let result;
      try {
        result = await post({ batch_key: crypto.randomUUID(), viewer_x_id: ready.viewer, responses });
      } catch {
        toastError("not reachable. Captures stay queued.");
        return setState({ lastError: "Xtend isn't reachable. Captures stay queued." });
      }
      // A single response Xtend refuses as too large would otherwise block the queue forever.
      const tooLarge = result.status === 413 && batchKeys.length === 1;
      if (!result.ok && !tooLarge) {
        toastError(result.body.error || `answered ${result.status}. Captures stay queued.`);
        return setState({ lastError: result.body.error || `Xtend answered ${result.status}. Captures stay queued.` });
      }
      await chrome.storage.local.remove(batchKeys);
      const current = await state();
      const byOperation = { ...current.byOperation };
      for (const item of responses) byOperation[item.operation] = Math.max((byOperation[item.operation] || 1) - 1, 0);
      const totals = { ...current.totals };
      for (const field of ["posts", "people_added", "people_updated", "likes", "bookmarks", "accounts", "interactions", "follows", "observations", "relationships", "unfollows", "lists_completed", "notifications", "analytics_days", "post_analytics", "analytics_hours"]) {
        totals[field] = (totals[field] || 0) + (result.body[field] || 0);
      }
      await setState({ pending: Math.max(current.pending - batchKeys.length, 0), byOperation, totals,
        lastSentAt: new Date().toISOString(), lastResult: tooLarge ? { dropped: 1 } : result.body, lastError: null });
      keys = keys.filter((key) => !batchKeys.includes(key));
      if (result.ok) announce(result.body);
    }
  });
}

async function testConnection() {
  const ready = await preflight();
  if (ready.error) return { ok: false, message: ready.error };
  try {
    const result = await post({ batch_key: crypto.randomUUID(), viewer_x_id: ready.viewer, responses: [] });
    return result.ok ? { ok: true, message: `Connected. Captures from X account ${ready.viewer} will be accepted.` }
      : { ok: false, message: result.body.error || `Xtend answered ${result.status}.` };
  } catch {
    return { ok: false, message: "Xtend isn't reachable at that address." };
  }
}

async function rawState() {
  const { rawState } = await chrome.storage.local.get("rawState");
  return { count: 0, bytes: 0, ...rawState };
}

// Raw keys carry the body size, so trimming the log never reads the bodies.
const rawKeys = () => keysWith(RAW_PREFIX);
const rawKeySize = (key) => Number(key.split("-")[1]) || 0;

function recordRaw(entry, tab) {
  return serial(async () => {
    if (!(await settings()).rawDebug) return;
    const key = `${RAW_PREFIX}${Date.now().toString().padStart(15, "0")}-${entry.body.length}-${crypto.randomUUID()}`;
    await chrome.storage.local.set({ [key]: { ...entry, page: tab?.url || null } });
    let { count, bytes } = await rawState();
    count += 1;
    bytes += entry.body.length;
    if (count > MAX_RAW_ENTRIES || bytes > MAX_RAW_BYTES) {
      const dropped = [];
      for (const old of await rawKeys()) {
        if (count <= MAX_RAW_ENTRIES && bytes <= MAX_RAW_BYTES) break;
        dropped.push(old);
        count -= 1;
        bytes -= rawKeySize(old);
      }
      await chrome.storage.local.remove(dropped);
    }
    await chrome.storage.local.set({ rawState: { count, bytes } });
  });
}

function clearRaw() {
  return serial(async () => {
    await chrome.storage.local.remove(await rawKeys());
    await chrome.storage.local.set({ rawState: { count: 0, bytes: 0 } });
  });
}

function clearQueue() {
  return serial(async () => {
    await chrome.storage.local.remove(await queuedKeys());
    return setState({ pending: 0, byOperation: {}, lastError: null });
  });
}

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (message.type === "capture") {
    if (sender.id === chrome.runtime.id && sender.tab) enqueue(message);
    return false;
  }
  if (message.type === "raw") {
    if (sender.id === chrome.runtime.id && sender.tab && typeof message.entry?.body === "string") recordRaw(message.entry, sender.tab);
    return false;
  }
  // The overlay on x.com asks what Xtend knows about the handles on screen. It gets that answer and nothing else.
  // A profile Xtend doesn't know yet: send the visit now instead of waiting for the next batch, then forget the
  // cached "unknown" so the overlay's next question gets the fresh answer.
  if (message.type === "save-now") {
    if (sender.id !== chrome.runtime.id || !sender.tab?.url?.startsWith("https://x.com/")) return false;
    const handle = String(message.handle || "").toLowerCase();
    new Promise((resolve) => setTimeout(resolve, SAVE_NOW_DELAY_MS)).then(() => flush()).catch(() => {})
      .then(() => { contextCache.delete(handle); reply({ ok: true }); });
    return true;
  }
  if (message.type === "context") {
    if (sender.id !== chrome.runtime.id || !sender.tab?.url?.startsWith("https://x.com/") || !Array.isArray(message.handles)) return false;
    context(message.handles).then(reply, () => reply({ error: "failed" }));
    return true;
  }
  // Everything else comes from the popup and options page. Content scripts run in x.com's renderer, so they get
  // nothing more here, and the tokens never leave this worker.
  // The options page opens in a tab, so the check is the sender's URL: only the extension's own pages have one here.
  if (sender.id !== chrome.runtime.id || !sender.url?.startsWith(chrome.runtime.getURL(""))) return false;
  const actions = {
    status: async () => {
      const { token, refreshToken, ...visible } = await settings();
      return { settings: { ...visible, connected: Boolean(token) }, state: await state(), raw: await rawState() };
    },
    "clear-raw": () => clearRaw(),
    flush: () => flush().then(state),
    clear: () => clearQueue(),
    test: () => testConnection(),
  };
  if (!actions[message.type]) return false;
  actions[message.type]().then(reply, (error) => reply({ ok: false, message: String(error) }));
  return true;
});

chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== "local" || !changes.settings) return;
  const before = changes.settings.oldValue || {};
  const after = changes.settings.newValue || {};
  if (before.overlay !== after.overlay || before.token !== after.token || before.xtendUrl !== after.xtendUrl) staleContext();
});

const schedule = () => chrome.alarms.create("flush", { periodInMinutes: 1 });
chrome.runtime.onInstalled.addListener(schedule);
chrome.runtime.onStartup.addListener(schedule);
chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name !== "flush") return;
  const [{ auto }, { pending }] = await Promise.all([settings(), state()]);
  if (auto && pending) flush();
});
