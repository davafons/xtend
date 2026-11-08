import { Controller } from "@hotwired/stimulus"
import { forceSimulation, forceLink, forceManyBody, forceCenter, forceCollide, forceX, forceY } from "d3-force"

// Draws the network as a force-directed graph on a canvas: avatars ringed in their follow relationship's color,
// arrows from who acted to who received it, weighted by how often. Two-way pairs curve apart so both arrows show. Selecting someone lists their connections in the panel.
const KIND_LABELS = {
  reply: ["reply", "replies"], quote: ["quote", "quotes"], repost: ["repost", "reposts"],
  mention: ["mention", "mentions"], like: ["like", "likes"], follow: ["follow", "follows"],
}

export default class extends Controller {
  static targets = ["canvas", "tooltip", "panel"]
  static values = { url: String }

  async connect() {
    this.colors = this.readColors()
    this.transform = { x: 0, y: 0, k: 1 }
    this.images = new Map()
    this.resizeObserver = new ResizeObserver(() => this.resize())
    this.resizeObserver.observe(this.canvasTarget)
    this.bindPointer()
    const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
    if (!response.ok) return
    this.load(await response.json())
  }

  disconnect() {
    this.simulation?.stop()
    this.resizeObserver?.disconnect()
  }

  readColors() {
    const style = getComputedStyle(document.documentElement)
    const read = (name) => style.getPropertyValue(name).trim()
    return {
      both: read("--success"), you: read("--crm-you"), them: read("--warning"), owner: read("--crm-you"),
      none: read("--border"), outside: read("--muted-foreground"), like: read("--crm-like"),
      line: read("--foreground"), muted: read("--muted-foreground"), card: read("--card"), text: read("--foreground"),
    }
  }

  load(data) {
    this.owner = data.owner
    this.nodes = data.nodes.map((node) => ({ ...node, radius: node.owner ? 22 : Math.min(7 + 3 * Math.sqrt(node.weight), 26) }))
    const byId = new Map(this.nodes.map((node) => [node.id, node]))
    this.links = data.links.filter((link) => byId.has(link.source) && byId.has(link.target)).map((link) => ({ ...link }))
    const directed = new Set(this.links.map((link) => `${link.source}>${link.target}`))
    for (const link of this.links) link.reciprocal = directed.has(`${link.target}>${link.source}`)
    this.neighbors = new Map(this.nodes.map((node) => [node.id, []]))
    for (const link of this.links) {
      this.neighbors.get(link.source).push({ id: link.target, link, outgoing: true })
      this.neighbors.get(link.target).push({ id: link.source, link, outgoing: false })
    }
    this.byId = byId
    for (const node of this.nodes) this.loadImage(node)
    this.resize()
    this.simulation = forceSimulation(this.nodes)
      .force("link", forceLink(this.links).id((node) => node.id)
        .distance((link) => link.source.radius + link.target.radius + 110 / Math.sqrt(link.weight)).strength(0.3))
      .force("charge", forceManyBody().strength(-420).distanceMax(600))
      .force("collide", forceCollide((node) => node.radius + 14))
      .force("center", forceCenter(0, 0))
      .force("x", forceX(0).strength(0.025))
      .force("y", forceY(0).strength(0.025))
      .on("tick", () => this.draw())
  }

  loadImage(node) {
    if (!node.avatar) return
    const image = new Image()
    image.referrerPolicy = "no-referrer"
    image.onload = () => this.draw()
    image.src = node.avatar
    this.images.set(node.id, image)
  }

  resize() {
    const canvas = this.canvasTarget
    const ratio = window.devicePixelRatio || 1
    this.width = canvas.clientWidth
    this.height = canvas.clientHeight
    canvas.width = this.width * ratio
    canvas.height = this.height * ratio
    this.ratio = ratio
    if (!this.centered && this.width) {
      this.transform = { x: this.width / 2, y: this.height / 2, k: 1 }
      this.centered = true
    }
    this.draw()
  }

  // Canvas coordinates for a pointer event, in graph space.
  point(event) {
    const box = this.canvasTarget.getBoundingClientRect()
    return { x: (event.clientX - box.left - this.transform.x) / this.transform.k, y: (event.clientY - box.top - this.transform.y) / this.transform.k }
  }

  nodeAt(event) {
    if (!this.nodes) return null
    const { x, y } = this.point(event)
    for (let index = this.nodes.length - 1; index >= 0; index--) {
      const node = this.nodes[index]
      if ((node.x - x) ** 2 + (node.y - y) ** 2 <= node.radius ** 2) return node
    }
    return null
  }

  bindPointer() {
    const canvas = this.canvasTarget
    canvas.addEventListener("wheel", (event) => {
      event.preventDefault()
      const box = canvas.getBoundingClientRect()
      const factor = Math.exp(-event.deltaY * 0.0015)
      const k = Math.min(Math.max(this.transform.k * factor, 0.2), 5)
      const mx = event.clientX - box.left
      const my = event.clientY - box.top
      this.transform.x = mx - ((mx - this.transform.x) * k) / this.transform.k
      this.transform.y = my - ((my - this.transform.y) * k) / this.transform.k
      this.transform.k = k
      this.draw()
    }, { passive: false })

    canvas.addEventListener("pointerdown", (event) => {
      canvas.setPointerCapture(event.pointerId)
      const node = this.nodeAt(event)
      this.drag = { node, startX: event.clientX, startY: event.clientY, x: this.transform.x, y: this.transform.y, moved: false }
      if (node) {
        node.fx = node.x
        node.fy = node.y
        this.simulation?.alphaTarget(0.2).restart()
      }
      canvas.classList.replace("cursor-grab", "cursor-grabbing")
    })

    canvas.addEventListener("pointermove", (event) => {
      if (this.drag) {
        const dx = event.clientX - this.drag.startX
        const dy = event.clientY - this.drag.startY
        if (Math.abs(dx) + Math.abs(dy) > 3) this.drag.moved = true
        if (this.drag.node) {
          const { x, y } = this.point(event)
          this.drag.node.fx = x
          this.drag.node.fy = y
        } else {
          this.transform.x = this.drag.x + dx
          this.transform.y = this.drag.y + dy
          this.draw()
        }
        return
      }
      const node = this.nodeAt(event)
      if (node !== this.hovered) {
        this.hovered = node
        canvas.style.cursor = node ? "pointer" : ""
        this.showTooltip(node, event)
        this.draw()
      } else if (node) {
        this.showTooltip(node, event)
      }
    })

    canvas.addEventListener("pointerup", (event) => {
      const drag = this.drag
      this.drag = null
      canvas.classList.replace("cursor-grabbing", "cursor-grab")
      if (drag?.node) {
        drag.node.fx = null
        drag.node.fy = null
        this.simulation?.alphaTarget(0)
      }
      if (drag && !drag.moved) this.select(drag.node)
    })

    canvas.addEventListener("pointerleave", () => {
      this.hovered = null
      this.showTooltip(null)
      this.draw()
    })
  }

  showTooltip(node, event) {
    if (!this.hasTooltipTarget) return
    if (!node) {
      this.tooltipTarget.hidden = true
      return
    }
    const box = this.canvasTarget.getBoundingClientRect()
    this.tooltipTarget.textContent = node.owner ? "You" : `${node.name} · @${node.handle}`
    this.tooltipTarget.style.transform = `translate(${event.clientX - box.left + 12}px, ${event.clientY - box.top + 12}px)`
    this.tooltipTarget.style.insetInlineStart = "0"
    this.tooltipTarget.style.top = "0"
    this.tooltipTarget.hidden = false
  }

  select(node) {
    this.selected = node
    this.draw()
    if (this.hasPanelTarget) this.renderPanel(node)
  }

  renderPanel(node) {
    const panel = this.panelTarget
    panel.replaceChildren()
    const heading = document.createElement("h2")
    heading.className = "text-lg font-semibold"
    if (!node) {
      heading.textContent = "Connections"
      const hint = document.createElement("p")
      hint.className = "text-sm text-muted-foreground"
      hint.textContent = "Select someone in the graph."
      panel.append(heading, hint)
      return
    }
    heading.textContent = node.owner ? "You" : node.name
    const meta = document.createElement("p")
    meta.className = "text-sm text-muted-foreground"
    meta.textContent = node.owner ? `@${node.handle}` : [`@${node.handle}`, node.follow_state, node.outside ? "Outside your CRM" : null].filter(Boolean).join(" · ")
    panel.append(heading, meta)
    if (node.person_id || node.outside) {
      const link = document.createElement("a")
      link.className = "text-sm text-you hover:underline"
      link.href = node.person_id ? `/people/${node.person_id}` : `https://x.com/${node.handle}`
      if (!node.person_id) {
        link.target = "_blank"
        link.rel = "noopener noreferrer"
      }
      link.textContent = node.person_id ? "Open person" : "View on X"
      panel.append(link)
    }
    const list = document.createElement("ol")
    list.className = "flex flex-col divide-y divide-border"
    const connections = this.connectionsOf(node)
    for (const connection of connections.slice(0, 30)) {
      const item = document.createElement("li")
      item.className = "flex flex-col gap-0.5 py-2"
      const name = document.createElement("button")
      name.type = "button"
      name.className = "cursor-pointer text-start text-sm font-medium hover:underline"
      name.textContent = connection.node.owner ? "You" : connection.node.name
      name.addEventListener("click", () => this.select(connection.node))
      item.append(name)
      for (const line of connection.lines) {
        const detail = document.createElement("span")
        detail.className = "text-xs text-muted-foreground"
        detail.textContent = line
        item.append(detail)
      }
      list.append(item)
    }
    if (connections.length === 0) {
      const none = document.createElement("p")
      none.className = "text-sm text-muted-foreground"
      none.textContent = "No connections in this view."
      panel.append(none)
    } else {
      panel.append(list)
    }
  }

  connectionsOf(node) {
    const merged = new Map()
    for (const { id, link, outgoing } of this.neighbors.get(node.id) || []) {
      const entry = merged.get(id) || { node: this.byId.get(id), weight: 0, out: {}, in: {} }
      entry.weight += link.weight
      for (const [kind, count] of Object.entries(link.kinds)) {
        const side = outgoing ? entry.out : entry.in
        side[kind] = (side[kind] || 0) + count
      }
      merged.set(id, entry)
    }
    const describe = (counts) => Object.entries(counts).map(([kind, count]) => `${count} ${KIND_LABELS[kind][count === 1 ? 0 : 1]}`).join(", ")
    const label = (other) => (other.owner ? "You" : `@${other.handle}`)
    return [...merged.values()].sort((a, b) => b.weight - a.weight).map((entry) => {
      const lines = []
      if (Object.keys(entry.out).length) lines.push(`${label(node)} → ${label(entry.node)}: ${describe(entry.out)}`)
      if (Object.keys(entry.in).length) lines.push(`${label(entry.node)} → ${label(node)}: ${describe(entry.in)}`)
      return { node: entry.node, lines }
    })
  }

  focusSet() {
    const focus = this.hovered || this.selected
    if (!focus) return null
    return new Set([focus.id, ...(this.neighbors.get(focus.id) || []).map((neighbor) => neighbor.id)])
  }

  linkColor(link) {
    const involvesOwner = link.source.id === this.owner || link.target.id === this.owner
    if (involvesOwner) return this.colors.you
    const kinds = Object.keys(link.kinds)
    if (kinds.length === 1 && kinds[0] === "like") return this.colors.like
    return this.colors.line
  }

  // A line from the source's ring to an arrowhead at the target's ring, bent to one side when the pair goes both ways.
  drawLink(context, link, k) {
    const { source, target } = link
    const dx = target.x - source.x
    const dy = target.y - source.y
    const distance = Math.hypot(dx, dy)
    if (distance <= source.radius + target.radius + 4 / k) return
    const bend = link.reciprocal ? Math.min(distance * 0.18, 40) : 0
    const cx = (source.x + target.x) / 2 - (dy / distance) * bend
    const cy = (source.y + target.y) / 2 + (dx / distance) * bend
    const edge = (node, gap) => {
      const ax = cx - node.x
      const ay = cy - node.y
      const length = Math.hypot(ax, ay) || 1
      return { x: node.x + (ax / length) * (node.radius + gap), y: node.y + (ay / length) * (node.radius + gap) }
    }
    const start = edge(source, 3 / k)
    const tip = edge(target, 4 / k)
    const lineWidth = (0.6 + Math.log2(link.weight + 1)) / Math.sqrt(k)
    const head = (7 + 1.5 * Math.log2(link.weight + 1)) / Math.sqrt(k)
    const ex = tip.x - cx
    const ey = tip.y - cy
    const length = Math.hypot(ex, ey) || 1
    const ux = ex / length
    const uy = ey / length
    const base = { x: tip.x - ux * head, y: tip.y - uy * head }

    const color = this.linkColor(link)
    context.strokeStyle = color
    context.fillStyle = color
    context.lineWidth = lineWidth
    context.setLineDash(link.kinds.follow && Object.keys(link.kinds).length === 1 ? [4 / k, 4 / k] : [])
    context.beginPath()
    context.moveTo(start.x, start.y)
    if (bend) context.quadraticCurveTo(cx, cy, base.x, base.y)
    else context.lineTo(base.x, base.y)
    context.stroke()
    context.setLineDash([])
    context.beginPath()
    context.moveTo(tip.x, tip.y)
    context.lineTo(base.x - uy * head * 0.55, base.y + ux * head * 0.55)
    context.lineTo(base.x + uy * head * 0.55, base.y - ux * head * 0.55)
    context.closePath()
    context.fill()
  }

  draw() {
    if (!this.nodes || !this.width) return
    const context = this.canvasTarget.getContext("2d")
    const { x, y, k } = this.transform
    context.setTransform(this.ratio, 0, 0, this.ratio, 0, 0)
    context.clearRect(0, 0, this.width, this.height)
    context.translate(x, y)
    context.scale(k, k)
    const focus = this.focusSet()

    for (const link of this.links) {
      if (typeof link.source !== "object") continue
      const active = !focus || (focus.has(link.source.id) && focus.has(link.target.id) && (link.source.id === (this.hovered || this.selected).id || link.target.id === (this.hovered || this.selected).id))
      context.globalAlpha = active ? (focus ? 0.9 : 0.35) : 0.05
      this.drawLink(context, link, k)
    }
    context.setLineDash([])

    for (const node of this.nodes) {
      const active = !focus || focus.has(node.id)
      context.globalAlpha = active ? 1 : 0.15
      const image = this.images.get(node.id)
      context.save()
      context.beginPath()
      context.arc(node.x, node.y, node.radius, 0, Math.PI * 2)
      context.closePath()
      if (image?.complete && image.naturalWidth) {
        context.clip()
        context.drawImage(image, node.x - node.radius, node.y - node.radius, node.radius * 2, node.radius * 2)
      } else {
        context.fillStyle = this.colors.muted
        context.fill()
      }
      context.restore()
      context.globalAlpha = active ? 1 : 0.15
      context.beginPath()
      context.arc(node.x, node.y, node.radius + 2 / k, 0, Math.PI * 2)
      context.strokeStyle = this.colors[node.relation] || this.colors.none
      context.lineWidth = (node === this.selected ? 4 : 2) / k
      context.setLineDash(node.outside ? [3 / k, 2 / k] : [])
      context.stroke()
      context.setLineDash([])

      const labelled = node === this.hovered || node === this.selected || node.owner || node.radius * k > 16 || (focus && focus.has(node.id))
      if (labelled && active) {
        context.font = `${12 / k}px system-ui, sans-serif`
        context.textAlign = "center"
        context.fillStyle = this.colors.text
        context.fillText(node.owner ? "You" : `@${node.handle}`, node.x, node.y + node.radius + 14 / k)
      }
    }
    context.globalAlpha = 1
  }
}
