// Queues captured responses in extension storage and sends them to the CRM in batches, on demand or every minute.
const DEFAULT_SETTINGS = { crmUrl: "https://twitter-crm.localhost", token: "", auto: true, paused: false };
const MAX_QUEUE = 2000;
const MAX_BATCH_RESPONSES = 50;
const MAX_BATCH_BYTES = 6 * 1024 * 1024;
const ITEM_PREFIX = "q:";

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

async function queuedKeys() {
  const all = await chrome.storage.local.get(null);
  return Object.keys(all).filter((key) => key.startsWith(ITEM_PREFIX)).sort();
}

function enqueue(message) {
  return serial(async () => {
    if ((await settings()).paused) return;
    const key = `${ITEM_PREFIX}${Date.now().toString().padStart(15, "0")}-${crypto.randomUUID()}`;
    await chrome.storage.local.set({ [key]: { operation: message.operation, variables: message.variables || {}, body: message.body } });
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
    if (auto && pending >= MAX_BATCH_RESPONSES) flush();
  });
}

async function viewerId() {
  const cookie = await chrome.cookies.get({ url: "https://x.com", name: "twid" });
  const match = cookie && decodeURIComponent(cookie.value).match(/u=(\d+)/);
  return match ? match[1] : null;
}

async function post(batch) {
  const { crmUrl, token } = await settings();
  const response = await fetch(`${crmUrl.replace(/\/+$/, "")}/x/captures`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify(batch),
  });
  const body = await response.json().catch(() => ({}));
  return { status: response.status, ok: response.ok, body };
}

async function preflight() {
  const { token } = await settings();
  if (!token) return { error: "Add your capture token in the extension options." };
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
        return setState({ lastError: "The CRM isn't reachable. Captures stay queued." });
      }
      // A single response the CRM refuses as too large would otherwise block the queue forever.
      const tooLarge = result.status === 413 && batchKeys.length === 1;
      if (!result.ok && !tooLarge) {
        return setState({ lastError: result.body.error || `The CRM answered ${result.status}. Captures stay queued.` });
      }
      await chrome.storage.local.remove(batchKeys);
      const current = await state();
      const byOperation = { ...current.byOperation };
      for (const item of responses) byOperation[item.operation] = Math.max((byOperation[item.operation] || 1) - 1, 0);
      const totals = { ...current.totals };
      for (const field of ["posts", "people_added", "people_updated", "likes", "bookmarks"]) {
        totals[field] = (totals[field] || 0) + (result.body[field] || 0);
      }
      await setState({ pending: Math.max(current.pending - batchKeys.length, 0), byOperation, totals,
        lastSentAt: new Date().toISOString(), lastResult: tooLarge ? { dropped: 1 } : result.body, lastError: null });
      keys = keys.filter((key) => !batchKeys.includes(key));
    }
  });
}

async function testConnection() {
  const ready = await preflight();
  if (ready.error) return { ok: false, message: ready.error };
  try {
    const result = await post({ batch_key: crypto.randomUUID(), viewer_x_id: ready.viewer, responses: [] });
    return result.ok ? { ok: true, message: `Connected. Captures from X account ${ready.viewer} will be accepted.` }
      : { ok: false, message: result.body.error || `The CRM answered ${result.status}.` };
  } catch {
    return { ok: false, message: "The CRM isn't reachable at that address." };
  }
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
  const actions = {
    status: async () => ({ settings: await settings(), state: await state() }),
    flush: () => flush().then(state),
    clear: () => clearQueue(),
    test: () => testConnection(),
  };
  if (!actions[message.type]) return false;
  actions[message.type]().then(reply, (error) => reply({ ok: false, message: String(error) }));
  return true;
});

const schedule = () => chrome.alarms.create("flush", { periodInMinutes: 1 });
chrome.runtime.onInstalled.addListener(schedule);
chrome.runtime.onStartup.addListener(schedule);
chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name !== "flush") return;
  const [{ auto }, { pending }] = await Promise.all([settings(), state()]);
  if (auto && pending) flush();
});
