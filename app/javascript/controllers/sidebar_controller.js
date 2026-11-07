import { Controller } from "@hotwired/stimulus"

// Collapses the sidebar to icons and remembers the choice in a cookie, so every page renders it the same way.
export default class extends Controller {
  static targets = ["toggle"]

  toggle() {
    const collapsed = !this.element.hasAttribute("data-collapsed")
    this.element.toggleAttribute("data-collapsed", collapsed)
    document.cookie = `sidebar=${collapsed ? "collapsed" : "expanded"}; path=/; max-age=31536000; samesite=lax`
    const label = collapsed ? "Expand sidebar" : "Collapse sidebar"
    this.toggleTarget.setAttribute("aria-label", label)
    this.toggleTarget.setAttribute("title", label)
    this.toggleTarget.setAttribute("aria-expanded", String(!collapsed))
  }
}
