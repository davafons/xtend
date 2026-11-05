import { Controller } from "@hotwired/stimulus"

// Refreshes the page (with morphing, keeping scroll) while a background X read is running.
// The server renders a new `at` value on each refresh, which schedules the next one; when no read
// is active the element is gone and refreshing stops.
export default class extends Controller {
  static values = { at: String, interval: { type: Number, default: 2000 } }

  atValueChanged() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => window.Turbo.visit(window.location.href, { action: "replace" }), this.intervalValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
