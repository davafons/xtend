const $ = (id) => document.getElementById(id);

async function load() {
  const { settings = {} } = await chrome.storage.local.get("settings");
  $("crmUrl").value = settings.crmUrl || "https://xtend.example.com";
  $("token").value = settings.token || "";
}

function show(text, ok) {
  $("message").textContent = text;
  $("message").className = ok ? "success" : "error";
}

$("save").addEventListener("click", async () => {
  let origin;
  try {
    origin = new URL($("crmUrl").value).origin;
  } catch {
    return show("Enter the full CRM address, starting with https://.", false);
  }
  // Addresses other than the default local one need permission; asking must happen inside this click.
  const granted = await chrome.permissions.request({ origins: [`${origin}/*`] }).catch(() => false);
  if (!granted && !(await chrome.permissions.contains({ origins: [`${origin}/*`] }))) {
    return show(`The extension needs permission to send to ${origin}.`, false);
  }
  const { settings = {} } = await chrome.storage.local.get("settings");
  await chrome.storage.local.set({ settings: { ...settings, crmUrl: origin, token: $("token").value.trim() } });
  show("Saved. Testing…", true);
  const result = await chrome.runtime.sendMessage({ type: "test" });
  show(result.message, result.ok);
});

load();
