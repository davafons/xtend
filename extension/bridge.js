// Runs in the extension's isolated world on x.com and relays page.js captures to the background worker.
// The page's own security policy blocks it from contacting the CRM; the background worker is not bound by it.
window.addEventListener("message", (event) => {
  if (event.source !== window || event.origin !== location.origin) return;
  const data = event.data;
  if (!data || data.source !== "twitter-crm-capture" || typeof data.body !== "string") return;
  chrome.runtime.sendMessage({ type: "capture", operation: data.operation, variables: data.variables, body: data.body, at: data.at })
    .catch(() => {});
});
