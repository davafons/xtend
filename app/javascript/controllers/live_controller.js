import { Controller } from "@hotwired/stimulus"

// Keeps open pages in step with the browser extension. The extension tells CRM tabs the moment a batch lands
// (a "crm:captured" window event); otherwise the page checks every 20 seconds while visible. New data refreshes
// the page in place (Turbo morph, scroll kept). While you are typing, have something expanded, or are on a page
// that marks itself data-live="manual", it offers a Refresh button instead of pulling the page from under you.
const POLL = 20_000

export default class extends Controller {
  static targets = ["status", "time", "summary", "dot", "ping", "notice"]
  static values = { url: String, capturedAt: String }

  connect() {
    this.check = this.check.bind(this)
    this.onVisible = () => { if (document.visibilityState === "visible") this.check() }
    window.addEventListener("crm:captured", this.check)
    document.addEventListener("visibilitychange", this.onVisible)
    this.timer = setInterval(() => { if (document.visibilityState === "visible") this.check() }, POLL)
    this.clock = setInterval(() => this.tick(), 15_000)
    this.tick()
  }

  disconnect() {
    window.removeEventListener("crm:captured", this.check)
    document.removeEventListener("visibilitychange", this.onVisible)
    clearInterval(this.timer)
    clearInterval(this.clock)
  }

  async check() {
    if (this.checking) return
    this.checking = true
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      if (!response.ok) return
      const { captured_at, summary } = await response.json()
      if (!captured_at || captured_at === this.capturedAtValue) return
      this.capturedAtValue = captured_at
      this.show(captured_at, summary)
      this.arrived()
    } catch {
      // Offline or signed out: the next check tries again.
    } finally {
      this.checking = false
    }
  }

  show(at, summary) {
    this.timeTarget.setAttribute("datetime", at)
    this.tick()
    if (summary) {
      this.summaryTarget.textContent = summary
      this.statusTarget.title = summary
    }
    this.dotTarget.classList.replace("bg-muted-foreground", "bg-grok")
    this.pingTarget.classList.add("animate-ping")
    this.pingTarget.classList.replace("opacity-0", "opacity-75")
    setTimeout(() => {
      this.pingTarget.classList.remove("animate-ping")
      this.pingTarget.classList.replace("opacity-75", "opacity-0")
    }, 2000)
  }

  arrived() {
    if (this.busy()) {
      this.offer()
    } else {
      this.refreshNow()
    }
  }

  // Typing, an expanded section, an open dialog, a text selection, or a page that asks for manual refreshes.
  busy() {
    const active = document.activeElement
    if (active && (active.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(active.tagName))) return true
    if (document.querySelector("dialog[open], [data-live=manual], main details[open], main [aria-expanded=true]")) return true
    return String(window.getSelection?.() || "").length > 0
  }

  offer() {
    if (document.querySelector("[data-live-notice]")) return
    this.element.append(this.noticeTarget.content.cloneNode(true))
  }

  refreshNow() {
    this.dismiss()
    window.Turbo.visit(window.location.href, { action: "replace" })
  }

  dismiss() {
    document.querySelectorAll("[data-live-notice]").forEach((notice) => notice.remove())
  }

  tick() {
    const at = this.timeTarget.getAttribute("datetime")
    if (!at) return
    const seconds = Math.max(0, Math.round((Date.now() - new Date(at)) / 1000))
    this.timeTarget.textContent = seconds < 45 ? "just now" : seconds < 3600 ? `${Math.round(seconds / 60)} min ago`
      : seconds < 86400 ? `${Math.round(seconds / 3600)} h ago` : `${Math.round(seconds / 86400)} d ago`
  }
}
