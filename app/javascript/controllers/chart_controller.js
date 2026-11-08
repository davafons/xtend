import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

// Draws a chart from the chart helper's JSON in the app's colors and type: 2px lines over a soft wash, rounded
// bars split by a thin gap, a hairline grid. Hovering shows every series at that point in an HTML tooltip.
// Legend buttons hide a series, and hovering one fades the others. Clicking a point opens its link; dragging
// across the chart opens the zoom URL for the dates under the selection.
const number = new Intl.NumberFormat("en")
const compact = new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 })
const day = new Intl.DateTimeFormat("en", { day: "numeric", month: "short" })
const hour = new Intl.DateTimeFormat("en", { day: "numeric", month: "short", hour: "numeric" })
const FADED = 0.2

export default class extends Controller {
  static targets = ["canvas", "tooltip"]
  static values = { config: Object }

  connect() {
    this.theme = this.readTheme()
    Chart.defaults.font.family = this.theme.font
    Chart.defaults.color = this.theme.text
    this.chart = new Chart(this.canvasTarget, this.options())
  }

  disconnect() {
    this.chart?.destroy()
    this.chart = null
  }

  toggle({ params: { index }, currentTarget }) {
    const visible = !this.chart.isDatasetVisible(index)
    this.chart.setDatasetVisibility(index, visible)
    currentTarget.setAttribute("aria-pressed", visible)
    this.chart.update()
  }

  focus({ params: { index } }) {
    this.highlight(index)
  }

  unfocus() {
    this.highlight(null)
  }

  press(event) {
    const x = this.pointerX(event)
    const { left, right } = this.chart.chartArea
    if (event.button !== 0 || x < left || x > right) return
    this.selection = { start: x, end: x }
    this.canvasTarget.setPointerCapture(event.pointerId)
  }

  drag(event) {
    if (!this.selection || !this.configValue.zoom) return
    const { left, right } = this.chart.chartArea
    this.selection.end = Math.min(Math.max(this.pointerX(event), left), right)
    this.chart.crmSelection = this.selection
    this.tooltipTarget.hidden = true
    this.chart.draw()
  }

  release(event) {
    const selection = this.selection
    this.cancel()
    if (!selection) return
    if (Math.abs(selection.end - selection.start) < 5) this.open(selection.start)
    else this.zoom(Math.min(selection.start, selection.end), Math.max(selection.start, selection.end))
  }

  cancel() {
    if (!this.selection) return
    this.selection = this.chart.crmSelection = null
    this.chart.draw()
  }

  open(pixel) {
    const url = this.configValue.links?.[this.barAt(pixel)]
    if (url) Turbo.visit(url)
  }

  // Bars cover whole buckets, so a selection snaps out to the first and last bar it touches.
  zoom(left, right) {
    const config = this.configValue
    const [from, to] = Array.isArray(config.x)
      ? [left, right].map((pixel) => isoDate(new Date(this.chart.scales.x.getValueForPixel(pixel))))
      : [config.dates[this.barAt(left)][0], config.dates[this.barAt(right)][1]]
    const url = new URL(config.zoom, location.href)
    url.searchParams.delete("period")
    url.searchParams.set("from", from)
    url.searchParams.set("to", to)
    Turbo.visit(url.toString())
  }

  // The bar whose column holds an x position on the canvas.
  barAt(pixel) {
    const index = Math.round(this.chart.scales.x.getValueForPixel(pixel))
    return Math.min(Math.max(index, 0), this.configValue.labels.length - 1)
  }

  pointerX(event) {
    return event.clientX - this.canvasTarget.getBoundingClientRect().left
  }

  highlight(index) {
    this.chart.data.datasets.forEach((dataset, i) => Object.assign(dataset, this.colors(dataset.rgb, index !== null && i !== index)))
    this.chart.update()
  }

  // Tokens are oklch; canvas gradients need channels, so each color is painted once and read back as RGB.
  readTheme() {
    const probe = document.createElement("span")
    this.element.append(probe)
    const pixel = document.createElement("canvas").getContext("2d", { willReadFrequently: true })
    const resolve = (name) => {
      probe.style.color = `var(${name})`
      pixel.clearRect(0, 0, 1, 1)
      pixel.fillStyle = getComputedStyle(probe).color
      pixel.fillRect(0, 0, 1, 1)
      return Array.from(pixel.getImageData(0, 0, 1, 1).data.slice(0, 3))
    }
    const theme = {
      text: rgba(resolve("--muted-foreground")), grid: rgba(resolve("--border"), 0.35),
      surface: rgba(resolve("--card")), band: rgba(resolve("--foreground"), 0.05),
      rule: rgba(resolve("--muted-foreground"), 0.5), font: getComputedStyle(this.element).fontFamily,
      selection: rgba(resolve("--crm-you"), 0.12), selectionEdge: rgba(resolve("--crm-you"), 0.6),
      series: this.configValue.series.map((series) => resolve(series.color)),
    }
    probe.remove()
    return theme
  }

  get line() {
    return this.configValue.type === "line"
  }

  colors(rgb, faded) {
    const color = rgba(rgb, faded ? FADED : 1)
    if (!this.line) return { backgroundColor: color, hoverBackgroundColor: color }
    return {
      borderColor: color, pointBackgroundColor: color, pointHoverBackgroundColor: color,
      backgroundColor: ({ chart }) => wash(chart, rgb, faded ? 0.03 : 0.2),
    }
  }

  options() {
    const config = this.configValue
    const time = Array.isArray(config.x)
    const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches
    const style = this.line ? {
      borderWidth: 2, borderCapStyle: "round", borderJoinStyle: "round", cubicInterpolationMode: "monotone",
      fill: "start", spanGaps: false, pointRadius: (context) => isolated(context) ? 3 : 0, pointHoverRadius: 5,
      pointHitRadius: 12, pointHoverBorderWidth: 2, pointHoverBorderColor: this.theme.surface,
    } : {
      borderRadius: 4, borderSkipped: false, borderWidth: { top: 0, right: 0, left: 0, bottom: config.stacked ? 2 : 0 },
      borderColor: this.theme.surface, maxBarThickness: 24, categoryPercentage: 0.72, barPercentage: 0.9,
    }
    const datasets = config.series.map((series, index) => {
      const rgb = this.theme.series[index]
      const data = time ? series.values.map((y, i) => ({ x: config.x[i], y })) : series.values
      return { label: series.name, data, rgb, ...style, ...this.colors(rgb, false) }
    })
    // Time ticks show the hour when the checks span less than three days.
    const short = time && config.x.at(-1) - config.x[0] < 3 * 24 * 3600 * 1000
    const ticks = { maxRotation: 0, autoSkipPadding: 20 }
    const cursor = config.links ? "pointer" : config.zoom ? "crosshair" : "default"
    if (config.ticks === "date") Object.assign(ticks, { maxTicksLimit: 6, callback: (value) => (short ? hour : day).format(value) })

    return {
      type: config.type,
      data: { labels: config.labels, datasets },
      plugins: [hoverPlugin],
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: reducedMotion ? false : { duration: 500, easing: "easeOutCubic" },
        interaction: { mode: "index", intersect: false, axis: "x" },
        events: ["mousemove", "mouseout"],
        onHover: (_event, elements, chart) => { chart.canvas.style.cursor = elements.length ? cursor : "default" },
        layout: { padding: { top: 6 } },
        scales: {
          x: {
            type: time ? "linear" : "category", stacked: config.stacked, offset: !this.line,
            min: time ? config.x[0] : undefined, max: time ? config.x.at(-1) : undefined,
            grid: { display: false }, border: { display: false },
            ticks,
          },
          y: {
            stacked: config.stacked, beginAtZero: !this.line, grace: this.line ? "10%" : 0,
            grid: { color: this.theme.grid, drawTicks: false }, border: { display: false },
            ticks: { maxTicksLimit: 4, precision: 0, padding: 8, callback: (value) => compact.format(value) },
          },
        },
        plugins: {
          legend: { display: false },
          tooltip: { enabled: false, external: (context) => this.renderTooltip(context) },
          crmHover: { band: this.theme.band, rule: this.theme.rule, line: this.line, selection: this.theme.selection, edge: this.theme.selectionEdge },
        },
      },
    }
  }

  // Values lead and series names follow; every visible series shows, including a missing value.
  renderTooltip({ chart, tooltip }) {
    const element = this.tooltipTarget
    if (tooltip.opacity === 0 || !tooltip.dataPoints?.length) {
      element.hidden = true
      return
    }
    const index = tooltip.dataPoints[0].dataIndex
    const config = this.configValue
    const title = node("div", "font-medium text-foreground", config.titles[index])
    const rows = config.series.map((series, i) => {
      if (!chart.isDatasetVisible(i)) return null
      const value = series.values[index]
      const row = node("div", "flex items-center gap-related")
      const key = node("span", this.line ? "h-0.5 w-3 shrink-0 rounded-full" : "size-2 shrink-0 rounded-sm")
      key.style.background = rgba(chart.data.datasets[i].rgb)
      row.append(key, node("span", "font-semibold tabular-nums text-foreground", value == null ? config.missing : number.format(value)), node("span", "text-muted-foreground", series.name))
      return row
    }).filter(Boolean)
    if (!this.line && config.stacked) rows.reverse()
    element.replaceChildren(title, ...rows)
    element.hidden = false

    const gap = 14
    const width = element.offsetWidth
    const left = tooltip.caretX + gap + width > chart.width ? tooltip.caretX - gap - width : tooltip.caretX + gap
    element.style.translate = `${Math.max(0, left)}px ${chart.chartArea.top}px`
  }
}

// A soft column behind the hovered bars, or a hairline through the hovered point on a line; while dragging, the
// selected span.
const hoverPlugin = {
  id: "crmHover",
  beforeDatasetsDraw(chart, _args, options) {
    const [active] = chart.getActiveElements()
    if (!active) return
    const { ctx, chartArea } = chart
    ctx.save()
    if (options.line) {
      ctx.strokeStyle = options.rule
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(Math.round(active.element.x) + 0.5, chartArea.top)
      ctx.lineTo(Math.round(active.element.x) + 0.5, chartArea.bottom)
      ctx.stroke()
    } else {
      const width = active.element.width + 12
      ctx.fillStyle = options.band
      ctx.beginPath()
      ctx.roundRect(active.element.x - width / 2, chartArea.top, width, chartArea.bottom - chartArea.top, 6)
      ctx.fill()
    }
    ctx.restore()
  },
  afterDatasetsDraw(chart, _args, options) {
    const selection = chart.crmSelection
    if (!selection || Math.abs(selection.end - selection.start) < 5) return
    const { ctx, chartArea: { top, bottom } } = chart
    const [left, right] = [selection.start, selection.end].sort((a, b) => a - b).map((x) => Math.round(x) + 0.5)
    ctx.save()
    ctx.fillStyle = options.selection
    ctx.fillRect(left, top, right - left, bottom - top)
    ctx.strokeStyle = options.edge
    ctx.lineWidth = 1
    ctx.beginPath()
    for (const x of [left, right]) {
      ctx.moveTo(x, top)
      ctx.lineTo(x, bottom)
    }
    ctx.stroke()
    ctx.restore()
  },
}

// The date in the browser's time zone, as YYYY-MM-DD.
function isoDate(date) {
  return date.toLocaleDateString("en-CA")
}

function rgba([r, g, b], alpha = 1) {
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

function wash(chart, rgb, alpha) {
  const area = chart.chartArea
  if (!area) return rgba(rgb, alpha)
  const gradient = chart.ctx.createLinearGradient(0, area.top, 0, area.bottom)
  gradient.addColorStop(0, rgba(rgb, alpha))
  gradient.addColorStop(1, rgba(rgb, 0))
  return gradient
}

// A point between two gaps has no line to sit on, so it keeps a visible dot.
function isolated({ dataset, dataIndex }) {
  const value = (i) => {
    const point = dataset.data[i]
    return point != null && typeof point === "object" ? point.y : point
  }
  return value(dataIndex) != null && value(dataIndex - 1) == null && value(dataIndex + 1) == null
}

function node(tag, className, text) {
  const element = document.createElement(tag)
  element.className = className
  if (text != null) element.textContent = text
  return element
}
