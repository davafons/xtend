// Shows what Xtend knows about the people x.com puts on screen: a ring in their follow relationship's color around
// every avatar, a small badge after their handle on posts and in lists, a line in X's own hover card, and a card at the top of the sidebar on a profile. It reads only the handles
// already on the page and asks the background worker, which asks Xtend; it never changes what X shows or sends.
// Everything it adds lives in closed shadow roots, so x.com's styles and scripts can't reach it.
(() => {
  const SCAN_DELAY_MS = 150;
  const HANDLE = /^@(\w{1,15})$/;
  const COLORS = {
    both: "oklch(78% 0.089 144.3deg)", you: "oklch(72% 0.14 245deg)", them: "oklch(80% 0.11 86deg)",
    muted: "#8b98a5", accent: "#96d1aa", warning: "oklch(80% 0.11 86deg)",
  };
  const TAG_HUES = {
    sky: "#7dd3fc", emerald: "#6ee7b7", amber: "#fcd34d", rose: "#fda4af", violet: "#c4b5fd",
    cyan: "#67e8f9", lime: "#bef264", orange: "#fdba74", fuchsia: "#f0abfc", indigo: "#a5b4fc",
  };
  // Heroicons (outline), as the app uses.
  const ICONS = {
    both: "M7.5 21 3 16.5m0 0L7.5 12M3 16.5h13.5m0-13.5L21 7.5m0 0L16.5 12M21 7.5H7.5",
    you: "m4.5 19.5 15-15m0 0H8.25m11.25 0v11.25",
    them: "m19.5 4.5-15 15m0 0h11.25m-11.25 0V8.25",
    neutral: "M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z",
    reply: "M2.25 12.76c0 1.6 1.123 2.994 2.707 3.227 1.087.16 2.185.283 3.293.369V21l4.076-4.076a1.526 1.526 0 0 1 1.037-.443 48.282 48.282 0 0 0 5.68-.494c1.584-.233 2.707-1.626 2.707-3.228V6.741c0-1.602-1.123-2.995-2.707-3.228A48.394 48.394 0 0 0 12 3c-2.392 0-4.744.175-7.043.513C3.373 3.746 2.25 5.14 2.25 6.741v6.018Z",
    pin: "M17.593 3.322c1.1.128 1.907 1.077 1.907 2.185V21L12 17.25 4.5 21V5.507c0-1.108.806-2.057 1.907-2.185a48.507 48.507 0 0 1 11.186 0Z",
    kept: "M9 12.75 11.25 15 15 9.75m-3-7.036A11.959 11.959 0 0 1 3.598 6 11.99 11.99 0 0 0 3 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285Z",
    bell: "M14.857 17.082a23.848 23.848 0 0 0 5.454-1.31A8.967 8.967 0 0 1 18 9.75V9A6 6 0 0 0 6 9v.75a8.967 8.967 0 0 1-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 0 1-5.714 0m5.714 0a3 3 0 1 1-5.714 0",
    open: "M13.5 6H5.25A2.25 2.25 0 0 0 3 8.25v10.5A2.25 2.25 0 0 0 5.25 21h10.5A2.25 2.25 0 0 0 18 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25",
  };
  const SHORT_FOLLOW = {
    Mutual: "Mutual", "You follow": "You follow", "You follow | follow-back unknown": "You follow",
    "Follows you": "Follows you", "Observed follower": "Follows you", Neither: "Not connected",
  };
  const STYLE = `
    :host { all: initial; font: 500 13px/1.3 system-ui, -apple-system, "Segoe UI", sans-serif; color: inherit; }
    * { box-sizing: border-box; }
    svg { width: 1em; height: 1em; flex-shrink: 0; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
    .chip { display: inline-flex; align-items: center; gap: 6px; padding: 1px 7px; border-radius: 999px; white-space: nowrap;
      font-size: 12px; color: ${COLORS.muted}; background: color-mix(in oklab, ${COLORS.muted} 12%, transparent); }
    .item { display: inline-flex; align-items: center; gap: 3px; }
    .you { color: ${COLORS.you}; } .them { color: ${COLORS.them}; } .both { color: ${COLORS.both}; } .neutral { color: ${COLORS.muted}; }
    .warning { color: ${COLORS.warning}; }
    .muted { color: ${COLORS.muted}; }
    .card { display: flex; flex-direction: column; gap: 10px; padding: 14px 16px; border-radius: 16px; color: inherit;
      border: 1px solid color-mix(in oklab, currentColor 18%, transparent); font-size: 14px; line-height: 1.4; }
    .head { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
    .brand { display: inline-flex; align-items: center; gap: 6px; font-weight: 700; color: ${COLORS.accent}; }
    .brand img { width: 18px; height: 18px; }
    a { color: ${COLORS.accent}; text-decoration: none; display: inline-flex; align-items: center; gap: 4px; font-size: 13px; }
    a:hover { text-decoration: underline; }
    .facts a { color: inherit; font-size: inherit; }
    .row { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; }
    .badge { display: inline-flex; align-items: center; gap: 4px; padding: 2px 8px; border-radius: 999px; font-size: 12px;
      background: color-mix(in oklab, currentColor 15%, transparent); }
    .facts { display: grid; grid-template-columns: auto 1fr; gap: 4px 12px; margin: 0; font-size: 13px; }
    .facts dt { color: ${COLORS.muted}; } .facts dd { margin: 0; }
    .tag { padding: 1px 8px; border-radius: 999px; font-size: 12px; background: color-mix(in oklab, currentColor 15%, transparent); }
    .notes { margin: 0; padding: 6px 10px; border-radius: 10px; font-size: 13px; white-space: pre-line;
      background: color-mix(in oklab, currentColor 7%, transparent); display: -webkit-box; -webkit-line-clamp: 4; -webkit-box-orient: vertical; overflow: hidden; }
    .line { display: flex; align-items: center; gap: 6px; font-size: 13px; }
    .hover { display: flex; flex-direction: column; gap: 6px; margin: 0 16px 14px; padding-top: 10px;
      border-top: 1px solid color-mix(in oklab, currentColor 18%, transparent); font-size: 13px; }
    .hover .notes { -webkit-line-clamp: 2; }
  `;

  const people = new Map();
  // Profiles asked to be saved right away: "pending", then "done" so a profile X never sends is asked only once.
  const saving = new Map();
  const asked = new Set();
  let status = { off: false, error: null };
  let scanTimer = null;
  let requesting = false;

  // --- reading the page ---

  const handleIn = (element) => {
    for (const span of element.querySelectorAll("span")) {
      const match = HANDLE.exec(span.textContent.trim());
      if (match) return match[1].toLowerCase();
    }
    return null;
  };

  function targets() {
    const found = [];
    for (const name of document.querySelectorAll('article [data-testid="User-Name"]')) {
      const handle = handleIn(name);
      // The handle row holds the handle, a dot, and the time; the badge goes after them.
      const link = [...name.querySelectorAll('a[href^="/"]')].find((a) => HANDLE.test(a.textContent.trim()));
      const row = link?.parentElement?.parentElement;
      if (handle && row) found.push({ kind: "chip", handle, element: name, place: (host) => row.append(host) });
    }
    for (const cell of document.querySelectorAll('[data-testid="UserCell"]')) {
      const handle = handleIn(cell);
      const link = [...cell.querySelectorAll('a[href^="/"]')].find((a) => HANDLE.test(a.textContent.trim()));
      const row = link?.parentElement?.parentElement;
      if (handle && row) found.push({ kind: "chip", handle, element: cell, place: (host) => row.append(host) });
    }
    for (const card of document.querySelectorAll('[data-testid="HoverCard"]')) {
      const handle = handleIn(card);
      const body = card.firstElementChild || card;
      if (handle) found.push({ kind: "hover", handle, element: card, place: (host) => body.append(host) });
    }
    for (const avatar of document.querySelectorAll('[data-testid^="UserAvatar-Container-"]')) {
      const handle = avatar.dataset.testid.slice("UserAvatar-Container-".length).toLowerCase();
      if (/^\w{1,15}$/.test(handle) && handle !== "unknown" && handle !== ownHandle()) found.push({ kind: "ring", handle, element: avatar });
    }
    const header = document.querySelector('[data-testid="primaryColumn"] [data-testid="UserName"]');
    const profile = header && handleIn(header);
    if (profile) found.push({ kind: "card", handle: profile, element: document.documentElement, place: (host) => placeCard(host, header) });
    return found;
  }

  // At the top of the sidebar, under X's search box (fixed, with an empty spacer behind it); beside the profile
  // header when the window is too narrow for a sidebar.
  function placeCard(host, header) {
    const sidebar = document.querySelector('[data-testid="sidebarColumn"]');
    const module = sidebar?.querySelector("aside, section[role=region]");
    let block = module;
    while (block?.parentElement && block.parentElement !== sidebar && block.parentElement.childElementCount < 3) block = block.parentElement;
    const first = block && [...block.parentElement.children].find((child) =>
      !child.dataset.xtendHost && child.textContent.trim() && !child.querySelector("form[role=search]") && getComputedStyle(child).position !== "fixed");
    if (first) first.before(host);
    else header.after(host);
  }

  // --- rendering ---

  const svg = (name) => {
    const element = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    element.setAttribute("viewBox", "0 0 24 24");
    element.setAttribute("aria-hidden", "true");
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", ICONS[name]);
    element.append(path);
    return element;
  };

  const el = (tag, className, ...children) => {
    const element = document.createElement(tag);
    if (className) element.className = className;
    element.append(...children.filter((child) => child !== null && child !== undefined && child !== false));
    return element;
  };

  function ago(iso) {
    if (!iso) return null;
    const days = Math.floor((Date.now() - new Date(iso).getTime()) / 86400000);
    if (days < 1) return "today";
    if (days < 14) return `${days}d`;
    if (days < 60) return `${Math.floor(days / 7)}w`;
    if (days < 365) return `${Math.floor(days / 30)}mo`;
    return `${Math.floor(days / 365)}y`;
  }

  function agoLong(iso) {
    const short = ago(iso);
    if (!short || short === "today") return short;
    const units = { d: "day", w: "week", mo: "month", y: "year" };
    const [, count, unit] = /^(\d+)(\w+)$/.exec(short);
    return `${count} ${units[unit]}${count === "1" ? "" : "s"} ago`;
  }

  const day = (iso) => new Date(`${iso}T00:00:00`).toLocaleDateString(undefined, { day: "numeric", month: "short" });

  function followBadge(person, className = "badge") {
    const label = SHORT_FOLLOW[person.follow];
    if (!label) return null;
    return el("span", `${className} ${person.meaning}`, svg(person.meaning), label);
  }

  function repliesItem(person) {
    const { from_you: you, from_them: them } = person.replies;
    if (!you && !them) return null;
    return el("span", "item", svg("reply"), el("span", "you", String(you)), "·", el("span", null, String(them)));
  }

  function summary(person) {
    return [
      person.follow,
      `${person.replies.from_you} replies from you, ${person.replies.from_them} from them`,
      person.latest?.label,
      person.tags.length ? person.tags.map((tag) => `#${tag.name}`).join(" ") : null,
      person.notes ? `Notes: ${person.notes}` : null,
      person.reminder ? `Reminder: ${person.reminder.reason} (${day(person.reminder.due_on)})` : null,
    ].filter(Boolean).join("\n");
  }

  function chip(person) {
    const items = [
      person.meaning !== "neutral" ? followBadge(person, "item") : null,
      repliesItem(person),
      person.last_reply_at ? el("span", "item", ago(person.last_reply_at)) : null,
      person.pinned ? el("span", "item you", svg("pin")) : null,
      person.reminder?.due ? el("span", "item warning", svg("bell")) : null,
    ].filter(Boolean);
    if (!items.length) return null;
    const node = el("span", "chip", ...items);
    node.title = `Xtend\n${summary(person)}`;
    return node;
  }

  function tags(person) {
    if (!person.tags.length) return null;
    return el("div", "row", ...person.tags.slice(0, 6).map((tag) => {
      const node = el("span", "tag", `#${tag.name}`);
      node.style.color = TAG_HUES[tag.hue] || COLORS.muted;
      return node;
    }));
  }

  function reminderLine(person) {
    if (!person.reminder) return null;
    return el("div", `line ${person.reminder.due ? "warning" : "muted"}`, svg("bell"), `${person.reminder.reason} · ${day(person.reminder.due_on)}`);
  }

  function hoverSection(person) {
    if (!person.known) return null;
    const row = el("div", "row", followBadge(person), repliesItem(person),
      person.last_reply_at ? el("span", "muted", `last reply ${agoLong(person.last_reply_at)}`) : null);
    return el("div", "hover", el("span", "brand", "xtend"), row, tags(person),
      person.notes ? el("p", "notes", person.notes) : null, reminderLine(person));
  }

  function card(person) {
    const brand = el("span", "brand");
    const icon = document.createElement("img");
    icon.src = chrome.runtime.getURL("icons/icon-32.png");
    icon.alt = "";
    brand.append(icon, "xtend");
    if (!person) {
      return el("div", "card", el("div", "head", brand),
        el("p", "muted", status.error === "not connected" ? "Connect the extension to Xtend in its options to see what Xtend knows here." : "Xtend isn't reachable right now."));
    }
    if (!person.known) {
      const text = saving.get(person.handle) === "pending" ? "Saving this profile to Xtend…"
        : "Not in Xtend yet. X didn't load this profile in a way Xtend saves; it shows here once it does.";
      return el("div", "card", el("div", "head", brand), el("p", "muted", text));
    }
    const open = el("a", null, "Open in Xtend", svg("open"));
    open.href = person.url;
    open.target = "_blank";
    open.rel = "noopener";
    const marks = el("div", "row", followBadge(person),
      person.pinned ? el("span", "badge you", svg("pin"), "Pinned") : null,
      person.kept ? el("span", "badge both", svg("kept"), "Kept") : null);
    const facts = el("dl", "facts");
    const fact = (term, ...value) => facts.append(el("dt", null, term), el("dd", null, ...value));
    const { from_you: you, from_them: them } = person.replies;
    fact("Replies", el("span", "you", `${you} from you`), ` · ${them} from them`);
    if (person.last_reply_at) fact("Last reply", agoLong(person.last_reply_at));
    if (person.latest) {
      const latest = el("a", null, person.latest.label.replace(" | ", " · "));
      latest.href = person.latest.url;
      latest.target = "_blank";
      latest.rel = "noopener";
      latest.title = "Every interaction of this kind, in Xtend";
      fact("Latest", latest);
    }
    return el("div", "card", el("div", "head", brand, open), marks, facts, tags(person),
      person.notes ? el("p", "notes", el("span", "muted", "Your notes: "), person.notes) : null, reminderLine(person));
  }

  // The ring sits on X's own avatar container, following its shape (round for people, rounded square for companies).
  const RING = { both: COLORS.both, you: COLORS.you, them: COLORS.them };
  let viewer;

  function ownHandle() {
    viewer ??= handleIn(document.querySelector('[data-testid="SideNav_AccountSwitcher_Button"]') || document.createElement("div"));
    return viewer;
  }

  function ringTitle(person) {
    if (person.follow === "Neither" && !person.known) {
      const checked = person.follow_checked_at ? ` (follow lists checked ${day(person.follow_checked_at.slice(0, 10))})` : "";
      return `Xtend: not following either way${checked}`;
    }
    return `Xtend: ${SHORT_FOLLOW[person.follow] || person.follow}`;
  }

  function ring(avatar, person) {
    const state = person ? `${person.meaning}:${person.follow}` : "none";
    avatar.dataset.xtendRing = `${avatar.dataset.testid}|${state}`;
    const color = person && RING[person.meaning];
    const neither = person?.follow === "Neither";
    if (!color && !neither) return unring(avatar, false);
    const shaped = [...avatar.querySelectorAll("div")].map((div) => getComputedStyle(div).borderRadius).find((radius) => radius && radius !== "0px");
    avatar.style.borderRadius = shaped || "9999px";
    avatar.style.outline = color ? `2px solid ${color}` : `1.5px dashed ${COLORS.muted}`;
    avatar.style.outlineOffset = "2px";
    avatar.title = ringTitle(person);
  }

  function unring(avatar, forget = true) {
    for (const property of ["outline", "outline-offset", "border-radius"]) avatar.style.removeProperty(property);
    avatar.removeAttribute("title");
    if (forget) delete avatar.dataset.xtendRing;
  }

  function host(kind, handle) {
    const node = document.createElement(kind === "chip" ? "span" : "div");
    node.dataset.xtendHost = kind;
    node.dataset.handle = handle;
    node.style.cssText = kind === "chip" ? "display:inline-flex;align-items:center;margin-inline-start:6px;flex-shrink:0"
      : kind === "card" ? "display:block;margin-bottom:16px" : "display:block";
    const root = node.attachShadow({ mode: "closed" });
    const style = document.createElement("style");
    style.textContent = STYLE;
    root.append(style);
    return { node, root };
  }

  const placed = new WeakMap();

  function render(target) {
    let person = people.get(target.handle);
    if (target.kind === "ring") return ring(target.element, person);
    if (target.kind === "card" && person && !person.known) {
      person = { ...person, handle: target.handle };
      if (!saving.has(target.handle)) saveNow(target.handle);
    }
    const content = target.kind === "chip" ? person?.known && chip(person)
      : target.kind === "hover" ? person && hoverSection(person)
      : card(person);
    if (!content) return;
    const { node, root } = host(target.kind, target.handle);
    root.append(content);
    if (target.kind === "card") node.dataset.state = person ? `data:${saving.get(target.handle) || ""}` : "error";
    target.place(node);
    if (target.kind !== "card") placed.set(target.element, node);
  }

  // --- the loop: find what's on screen, ask for what's missing, render what's known ---

  function current(target) {
    if (target.kind === "ring") {
      const person = people.get(target.handle);
      return target.element.dataset.xtendRing === `${target.element.dataset.testid}|${person ? `${person.meaning}:${person.follow}` : "none"}`;
    }
    if (target.kind === "card") {
      const existing = document.querySelector('[data-xtend-host="card"]');
      const state = people.has(target.handle) ? `data:${saving.get(target.handle) || ""}` : "error";
      if (existing?.dataset.handle === target.handle && existing.dataset.state === state && existing.isConnected) return true;
      existing?.remove();
      return false;
    }
    const existing = placed.get(target.element);
    if (existing?.isConnected && existing.dataset.handle === target.handle) return true;
    existing?.remove();
    placed.delete(target.element);
    return false;
  }

  function scan() {
    scanTimer = null;
    if (status.off) return;
    const pending = targets().filter((target) => !current(target));
    const missing = [...new Set(pending.map((target) => target.handle))].filter((handle) => !people.has(handle) && !asked.has(handle));
    for (const target of pending) {
      if (people.has(target.handle) || (target.kind === "card" && status.error)) render(target);
    }
    if (missing.length && !requesting) request(missing);
  }

  async function request(handles) {
    requesting = true;
    handles.forEach((handle) => asked.add(handle));
    try {
      const answer = await chrome.runtime.sendMessage({ type: "context", handles });
      if (answer?.off) {
        status = { off: true, error: null };
        clear();
        return;
      }
      status = { off: false, error: answer?.error || null };
      for (const [handle, person] of Object.entries(answer?.people || {})) people.set(handle, person);
    } catch {
      status = { off: false, error: "unreachable" };
    } finally {
      // An unanswered handle can be asked again on a later scan.
      handles.filter((handle) => !people.has(handle)).forEach((handle) => asked.delete(handle));
      requesting = false;
    }
    schedule();
  }

  async function saveNow(handle) {
    saving.set(handle, "pending");
    try {
      await chrome.runtime.sendMessage({ type: "save-now", handle });
    } catch {}
    saving.set(handle, "done");
    people.delete(handle);
    asked.delete(handle);
    schedule();
  }

  function clear() {
    for (const node of document.querySelectorAll("[data-xtend-host]")) node.remove();
    for (const avatar of document.querySelectorAll("[data-xtend-ring]")) unring(avatar);
  }

  const schedule = () => { scanTimer ||= setTimeout(scan, SCAN_DELAY_MS); };

  chrome.runtime.onMessage.addListener((message) => {
    if (message?.type !== "context-stale") return;
    people.clear();
    asked.clear();
    status = { off: false, error: null };
    clear();
    schedule();
  });

  new MutationObserver((records) => {
    // Our own hosts going in or out don't need another scan.
    if (records.every((record) => [...record.addedNodes, ...record.removedNodes].every((node) => node.dataset?.xtendHost))) return;
    schedule();
  }).observe(document.body, { childList: true, subtree: true });
  schedule();
})();
