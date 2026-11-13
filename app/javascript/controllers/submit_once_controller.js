import { Controller } from "@hotwired/stimulus"

// Disables every button inside after the first submit, for forms that leave the app (so Turbo's own
// submits-with doesn't apply) and whose next page can take a while to answer.
export default class extends Controller {
  static values = { label: { type: String, default: "Working…" } }

  submit(event) {
    const submitter = event.submitter
    setTimeout(() => {
      this.element.querySelectorAll("button").forEach((button) => { button.disabled = true })
      if (submitter) submitter.textContent = submitter.dataset.submitOnceLabel || this.labelValue
    })
  }
}
