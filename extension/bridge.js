// Runs in the extension's isolated world on x.com and relays page.js captures to the background worker.
// The page's own security policy blocks it from contacting the CRM; the background worker is not bound by it.
window.addEventListener("message", (event) => {
  if (event.source !== window || event.origin !== location.origin) return;
  const data = event.data;
  if (!data || data.source !== "twitter-crm-capture" || typeof data.body !== "string") return;
  chrome.runtime.sendMessage({ type: "capture", operation: data.operation, variables: data.variables, body: data.body, at: data.at })
    .catch(() => {});
});

// A small notice from the CRM, such as follow-list progress while you scroll. It lives in a shadow root so x.com's
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
      "color:#fff;background:rgba(15,20,25,.92);box-shadow:0 4px 16px rgba(0,0,0,.4);transition:opacity .2s;opacity:0";
    root.append(toast);
    document.documentElement.append(host);
  }
  toast.textContent = message.text;
  toast.style.borderLeft = `3px solid ${message.tone === "error" ? "#f4212e" : "#00ba7c"}`;
  toast.style.opacity = "1";
  clearTimeout(toast.hideTimer);
  toast.hideTimer = setTimeout(() => { toast.style.opacity = "0"; }, message.tone === "error" ? 8000 : 5000);
});
