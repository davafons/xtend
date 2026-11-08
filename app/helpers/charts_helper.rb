# Charts drawn by the chart Stimulus controller with Chart.js. Each series takes a meaning color from tokens.css,
# so a chart uses the same colors as badges and avatar rings. The legend and a screen-reader table come from
# the server; the canvas, hover tooltip, and legend interactions come from the controller.
module ChartsHelper
  CHART_COLORS = { you: "--crm-you", like: "--crm-like", message: "--crm-message", grok: "--crm-grok",
    both: "--success", them: "--warning", neutral: "--muted-foreground" }.freeze
  CHART_KEYS = { you: "bg-you", like: "bg-like", message: "bg-message", grok: "bg-grok",
    both: "bg-success", them: "bg-warning", neutral: "bg-muted-foreground" }.freeze

  # type: :bar or :line. labels name each point on the axis; titles, when given, name it in the tooltip and the
  # table. series: [{ name:, meaning:, values: }], with nil for a missing value, which draws as a gap. x: numeric
  # positions, such as epoch milliseconds, places points on a time axis instead of evenly spaced labels, and
  # ticks: "date" formats that axis. missing: the tooltip text for a nil value.
  #
  # links: a URL per point, opened by clicking it. zoom: a URL that dragging across the chart opens with from and to
  # date params; dates: the [first, last] Date each point covers, which bars need for that, while a time axis
  # converts its own positions.
  def chart(type, label:, labels:, series:, titles: labels, x: nil, ticks: nil, stacked: false, missing: "No data",
    links: nil, zoom: nil, dates: nil, **options)
    config = { type: type, labels: labels, titles: titles, x: x, ticks: ticks, stacked: stacked, missing: missing,
      links: links, zoom: zoom, dates: dates&.map { |range| range.map(&:iso8601) },
      series: series.map { |item| { name: item[:name], color: CHART_COLORS.fetch(item[:meaning]), values: item[:values] } } }
    options[:class] = [ "flex flex-col gap-related", options[:class] ].compact.join(" ")
    tag.figure(**options, data: { controller: "chart", chart_config_value: config.to_json }) do
      safe_join([
        tag.figcaption(label, class: "sr-only"),
        (chart_legend(series, bars: type == :bar) if series.size > 1),
        tag.div(class: "relative h-56") do
          safe_join([
            tag.canvas(role: "img", aria: { label: label }, data: { chart_target: "canvas",
              action: ("pointerdown->chart#press pointermove->chart#drag pointerup->chart#release pointercancel->chart#cancel keydown.esc@window->chart#cancel" if links || zoom) }),
            tag.div(hidden: true, data: { chart_target: "tooltip" },
              class: "pointer-events-none absolute start-0 top-0 z-10 flex min-w-36 flex-col gap-tight rounded-lg bg-popover px-related py-tight text-caption shadow-lg transition-[translate] duration-100 ease-out")
          ])
        end,
        chart_table(label, titles, series, links)
      ].compact)
    end
  end

  private

  # Buttons hide a series; hovering or focusing one fades the others. Keys mirror the marks;
  # bar legends also show each series' total.
  def chart_legend(series, bars:)
    tag.ul(class: "flex flex-wrap items-center gap-x-content gap-y-tight", aria: { label: "Series" }) do
      safe_join(series.each_with_index.map do |item, index|
        tag.li do
          tag.button(type: "button", aria: { pressed: true },
            class: "flex cursor-pointer items-center gap-related rounded-sm text-small text-muted-foreground transition-opacity hover:text-foreground aria-[pressed=false]:opacity-40",
            data: { action: "chart#toggle mouseenter->chart#focus mouseleave->chart#unfocus focus->chart#focus blur->chart#unfocus", chart_index_param: index }) do
            safe_join([
              tag.span(class: "#{bars ? "size-2.5 rounded-sm" : "h-0.5 w-3 rounded-full"} #{CHART_KEYS.fetch(item[:meaning])}", aria: { hidden: true }),
              item[:name],
              (tag.span(number_with_delimiter(item[:values].compact.sum), class: "tabular-nums text-foreground") if bars)
            ].compact)
          end
        end
      end)
    end
  end

  def chart_table(label, labels, series, links)
    tag.table(class: "sr-only") do
      safe_join([
        tag.caption(label),
        tag.thead { tag.tr { safe_join([ tag.th("", scope: "col"), *series.map { |item| tag.th(item[:name], scope: "col") } ]) } },
        tag.tbody do
          safe_join(labels.each_with_index.map do |row, index|
            tag.tr { safe_join([ tag.th(links&.[](index) ? link_to(row, links[index]) : row, scope: "row"), *series.map { |item| tag.td(item[:values][index]&.then { number_with_delimiter(_1) } || "—") } ]) }
          end)
        end
      ])
    end
  end
end
