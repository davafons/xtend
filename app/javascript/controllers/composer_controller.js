import { Controller } from "@hotwired/stimulus"

// Live X-style weighted character count and thread preview for the composer.
const LIMIT = 280
const URL = /https?:\/\/\S+/g
const SEPARATOR = /^\s*---\s*$/m

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
  static targets = ["input", "preview", "summary", "intent"]
  static values = { handle: String }

  connect() {
    this.render()
  }

  render() {
    const parts = this.inputTarget.value.split(SEPARATOR).map((part) => part.trim()).filter(Boolean)
    this.previewTarget.replaceChildren(...parts.map((part, index) => this.card(part, index, parts.length)))
    const over = parts.filter((part) => weightedLength(part) > LIMIT).length
    this.summaryTarget.textContent = parts.length === 0 ? "Empty draft"
      : `${parts.length === 1 ? "Single post" : `Thread of ${parts.length}`}${over ? ` · ${over} over ${LIMIT}` : ""}`
    this.summaryTarget.classList.toggle("text-danger", over > 0)
    if (this.hasIntentTarget) {
      this.intentTarget.href = `https://x.com/intent/post?text=${encodeURIComponent(parts[0] || "")}`
    }
  }

  insertBreak() {
    const input = this.inputTarget
    const position = input.selectionEnd
    input.setRangeText("\n\n---\n\n", position, position, "end")
    input.focus()
    this.render()
  }

  card(text, index, total) {
    const length = weightedLength(text)
    const card = document.createElement("div")
    card.className = "crm-post-preview flex flex-col gap-2 rounded-2xl border border-border p-4"
    const body = document.createElement("p")
    body.className = "whitespace-pre-wrap break-words text-sm"
    body.textContent = text
    const meta = document.createElement("div")
    meta.className = "flex items-center justify-between text-xs tabular-nums text-muted"
    const position = document.createElement("span")
    position.textContent = total > 1 ? `${index + 1}/${total}` : ""
    const count = document.createElement("span")
    count.textContent = `${length}/${LIMIT}`
    if (length > LIMIT) count.className = "font-semibold text-danger"
    else if (length > LIMIT - 20) count.className = "font-semibold text-warning"
    meta.append(position, count)
    card.append(body, meta)
    return card
  }
}
