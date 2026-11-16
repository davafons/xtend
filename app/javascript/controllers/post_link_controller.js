import { Controller } from "@hotwired/stimulus"

// Opens a post's page when you click anywhere on it, as x.com does. Links, buttons, and media inside keep
// their own clicks, selecting text doesn't navigate, and Cmd/Ctrl-click or middle-click opens a new tab.
export default class extends Controller {
  static values = { url: String }

  open(event) {
    if (event.target.closest("a, button, video, input, select, textarea, label, summary, [data-post-link-ignore]")) return
    // A quoted post inside this one opens its own page.
    if (event.target.closest("[data-controller~='post-link']") !== this.element) return
    if (window.getSelection()?.toString()) return
    if (event.metaKey || event.ctrlKey || event.button === 1) {
      window.open(this.urlValue, "_blank", "noopener")
    } else if (event.button === 0) {
      window.Turbo.visit(this.urlValue)
    }
  }
}
