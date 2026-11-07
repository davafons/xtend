import { Controller } from "@hotwired/stimulus"

// Collapses the sidebar to icons and remembers the choice in a cookie, so every page renders it the same way.
// Below 1280px it starts collapsed unless you expanded it, so the state is read from its rendered width.
export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    this.label()
  }

  toggle() {
    const collapse = !this.collapsed
    this.element.toggleAttribute("data-collapsed", collapse)
    this.element.toggleAttribute("data-expanded", !collapse)
    document.cookie = `sidebar=${collapse ? "collapsed" : "expanded"}; path=/; max-age=31536000; samesite=lax`
    this.label()
  }

  get collapsed() {
    return this.element.getBoundingClientRect().width < 120
  }

  label() {
    const collapsed = this.collapsed
    const label = collapsed ? "Expand sidebar" : "Collapse sidebar"
    this.toggleTarget.setAttribute("aria-label", label)
    this.toggleTarget.setAttribute("title", label)
    this.toggleTarget.setAttribute("aria-expanded", String(!collapsed))
  }
}
