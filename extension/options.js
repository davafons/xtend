import { connect, revoke } from "./oauth.js";

const $ = (id) => document.getElementById(id);

async function current() {
  const { settings = {} } = await chrome.storage.local.get("settings");
  return settings;
}

async function load() {
  const settings = await current();
  $("xtendUrl").value = settings.xtendUrl || "https://xtend.example.com";
  $("token").value = settings.refreshToken ? "" : settings.token || "";
  $("status").textContent = settings.refreshToken ? `Connected to ${settings.xtendUrl}.` : settings.token ? "Using a pasted token." : "Not connected.";
  $("disconnect").hidden = !settings.token;
}

function show(text, ok) {
  $("message").textContent = text;
  $("message").className = ok ? "success" : "error";
}

// Addresses other than the built-in ones need permission; asking must happen inside the click.
async function permittedOrigin() {
  let origin;
  try {
    origin = new URL($("xtendUrl").value).origin;
  } catch {
    show("Enter the full Xtend address, starting with https://.", false);
    return null;
  }
  const granted = await chrome.permissions.request({ origins: [`${origin}/*`] }).catch(() => false);
  if (!granted && !(await chrome.permissions.contains({ origins: [`${origin}/*`] }))) {
    show(`The extension needs permission to reach ${origin}.`, false);
    return null;
  }
  return origin;
}

async function save(changes) {
  await chrome.storage.local.set({ settings: { ...(await current()), ...changes } });
  await load();
  show("Saved. Testing…", true);
  const result = await chrome.runtime.sendMessage({ type: "test" });
  show(result?.message || "The extension didn't answer the connection test. Reload it and try again.", Boolean(result?.ok));
}

$("connect").addEventListener("click", async () => {
  const origin = await permittedOrigin();
  if (!origin) return;
  try {
    await save({ xtendUrl: origin, ...(await connect(origin)) });
  } catch (error) {
    show(error.message, false);
  }
});

$("disconnect").addEventListener("click", async () => {
  const settings = await current();
  if (settings.refreshToken) await revoke(settings.xtendUrl, settings.refreshToken);
  await chrome.storage.local.set({ settings: { ...settings, token: "", refreshToken: "", expiresAt: null } });
  await load();
  show("Disconnected.", true);
});

$("save").addEventListener("click", async () => {
  const origin = await permittedOrigin();
  if (origin) await save({ xtendUrl: origin, token: $("token").value.trim(), refreshToken: "", expiresAt: null });
});

load();
