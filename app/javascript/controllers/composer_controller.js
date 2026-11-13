import { Controller } from "@hotwired/stimulus"

// An X-style composer: one growing textarea per post, a thread line between them, and X's
// weighted character count shown as a ring for the post being edited.
const LIMIT = 280
const URL = /https?:\/\/\S+/g

function weight(char) {
  const code = char.codePointAt(0)
  return code <= 4351 || (code >= 8192 && code <= 8205) || (code >= 8208 && code <= 8223) || (code >= 8242 && code <= 8247) ? 1 : 2
}

export function weightedLength(text) {
  let total = 0
  for (const char of text.normalize("NFC").replace(URL, "x".repeat(23))) total += weight(char)
  return total
}

export default class extends Controller {
  static targets = ["list", "part", "input", "template", "divider", "summary", "intent", "submit"]
  static values = { required: Boolean }

  connect() {
    this.active = this.inputTargets[0]
    this.inputTargets.forEach((input) => this.grow(input))
    this.render()
  }

  edit(event) {
    this.active = event.target
    this.grow(event.target)
    this.render()
  }

  focus(event) {
    this.active = event.target
    this.render()
  }

  add() {
    const fragment = this.templateTarget.content.cloneNode(true)
    this.listTarget.append(fragment)
    const input = this.inputTargets.at(-1)
    input.focus()
    this.active = input
    this.render()
  }

  remove(event) {
    const part = event.target.closest("[data-composer-target='part']")
    if (this.partTargets.length <= 1) return
    part.remove()
    this.active = this.inputTargets.at(-1)
    this.active.focus()
    this.render()
  }

  grow(input) {
    input.style.height = "auto"
    input.style.height = `${input.scrollHeight}px`
  }

  render() {
    const texts = this.inputTargets.map((input) => input.value.trim())
    this.inputTargets.forEach((input, index) => {
      input.setAttribute("aria-label", this.inputTargets.length > 1 ? `Post ${index + 1} of ${this.inputTargets.length}` : "Post")
      input.closest("[data-composer-target='part']").querySelector("[data-remove]")?.toggleAttribute("hidden", this.inputTargets.length <= 1)
    })
    this.renderRing(weightedLength(this.active?.value || ""))
    if (this.hasSummaryTarget) {
      const filled = texts.filter(Boolean)
      const over = filled.filter((text) => weightedLength(text) > LIMIT).length
      this.summaryTarget.textContent = filled.length > 1 ? `Thread of ${filled.length}${over ? `, ${over} too long` : ""}` : ""
    }
    if (this.requiredValue && this.hasSubmitTarget) this.submitTarget.disabled = !texts.some(Boolean)
    if (this.hasIntentTarget) {
      this.intentTarget.href = `https://x.com/intent/post?text=${encodeURIComponent(texts.find(Boolean) || "")}`
    }
  }

  // lc_char_counter draws the ring from X's weighted count of the post being edited.
  renderRing(length) {
    this.dispatch("count", { detail: { count: length } })
    if (this.hasDividerTarget) this.dividerTarget.toggleAttribute("hidden", length === 0)
  }
}
