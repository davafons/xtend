// Runs in the extension's isolated world on x.com and relays page.js captures to the background worker.
// The page's own security policy blocks it from contacting Xtend; the background worker is not bound by it.
window.addEventListener("message", (event) => {
  if (event.source !== window || event.origin !== location.origin) return;
  const data = event.data;
  if (!data || data.source !== "xtend-capture" || typeof data.body !== "string") return;
  chrome.runtime.sendMessage({ type: "capture", operation: data.operation, variables: data.variables, body: data.body, at: data.at })
    .catch(() => {});
});

// The raw debug log: tells page.js whether to copy every X API response, and relays the copies.
const postRawSetting = (settings) =>
  window.postMessage({ source: "xtend-config", raw: settings?.rawDebug === true }, location.origin);
chrome.storage.local.get("settings").then(({ settings }) => postRawSetting(settings)).catch(() => postRawSetting(null));
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === "local" && changes.settings) postRawSetting(changes.settings.newValue);
});
window.addEventListener("message", (event) => {
  if (event.source !== window || event.origin !== location.origin) return;
  const data = event.data;
  if (!data || data.source !== "xtend-raw" || typeof data.body !== "string") return;
  const { source, ...entry } = data;
  chrome.runtime.sendMessage({ type: "raw", entry }).catch(() => {});
});

// A small notice from Xtend, such as follow-list progress while you scroll. It lives in a shadow root so x.com's
// styles can't reach it, and it never blocks the page.
let toast;
chrome.runtime.onMessage.addListener((message) => {
  if (message?.type !== "toast" || typeof message.text !== "string") return;
  if (!toast) {
    const host = document.createElement("div");
    host.style.cssText = "position:fixed;left:16px;bottom:16px;z-index:2147483647;pointer-events:none";
    const root = host.attachShadow({ mode: "closed" });
    toast = document.createElement("div");
    toast.setAttribute("role", "status");
    toast.style.cssText = "max-width:340px;padding:10px 14px;border-radius:14px;font:500 13px/1.4 system-ui,sans-serif;" +
      "color:#f2f4f8;background:rgba(18,22,29,.82);-webkit-backdrop-filter:blur(24px) saturate(160%);backdrop-filter:blur(24px) saturate(160%);" +
      "box-shadow:inset 0 1px 0 rgba(255,255,255,.06),0 8px 24px rgba(0,0,0,.45);transition:opacity .2s;opacity:0";
    root.append(toast);
    document.documentElement.append(host);
  }
  toast.textContent = message.text;
  toast.style.borderLeft = `3px solid ${message.tone === "error" ? "oklch(80% 0.11 86deg)" : "#46e3a0"}`;
  toast.style.opacity = "1";
  clearTimeout(toast.hideTimer);
  toast.hideTimer = setTimeout(() => { toast.style.opacity = "0"; }, message.tone === "error" ? 8000 : 5000);
});
