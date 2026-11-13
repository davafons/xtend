// Runs on CRM pages. When the background worker delivers a batch, it tells the page, which refreshes itself.
chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === "captured") window.dispatchEvent(new CustomEvent("crm:captured"));
});
