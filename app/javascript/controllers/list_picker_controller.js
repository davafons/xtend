import { Controller } from "@hotwired/stimulus"

// Points the form at the list picked in its select, so one Add button serves every list.
export default class extends Controller {
  connect() {
    this.pick()
  }

  pick() {
    const select = this.element.querySelector("select")
    if (select?.value) this.element.action = select.value
  }
}
