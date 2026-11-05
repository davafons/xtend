import { Controller } from "@hotwired/stimulus"

// Remembers which tweets were opened on X in this browser tab, so the card
// still says "Opened on X" after returning or after a morph refresh.
const KEY = "crm:opened-posts"

export default class extends Controller {
  static values = { id: String }
  static targets = ["hint", "reply"]

  connect() {
    this.apply = this.apply.bind(this)
    document.addEventListener("turbo:morph", this.apply)
    this.apply()
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this.apply)
  }

  opened() {
    const ids = this.openedIds()
    ids.add(this.idValue)
    sessionStorage.setItem(KEY, JSON.stringify([...ids]))
    this.apply()
  }

  apply() {
    const opened = this.openedIds().has(this.idValue)
    this.element.toggleAttribute("data-opened", opened)
    this.hintTargets.forEach((hint) => { hint.hidden = !opened })
  }

  openedIds() {
    try {
      return new Set(JSON.parse(sessionStorage.getItem(KEY) || "[]"))
    } catch {
      return new Set()
    }
  }
}
