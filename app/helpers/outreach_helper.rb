module OutreachHelper
  # A CRM person links to their page and carries a follow ring; an account seen only in captures has neither.
  def outreach_avatar(author, graph)
    if author.is_a?(Person)
      link_to(person_avatar(author, ring: author.follow_state(graph)), author, tabindex: -1, aria: { hidden: true })
    elsif author&.avatar_url.present? && !demo?
      lc_avatar(src: author.avatar_image_url, alt: "", referrerpolicy: "no-referrer", loading: "lazy")
    else
      lc_avatar(author&.name.to_s.first(2).upcase.presence || "?")
    end
  end

  # One reason as its icon in the reason's meaning color, then the short detail; the full note is the title.
  def outreach_reason(reason)
    tag.span(class: "inline-flex min-w-0 items-center gap-tight", title: reason.note) do
      safe_join([
        lc_icon(reason.icon, options: { class: "size-4 shrink-0 #{ApplicationHelper::MEANING_TEXT.fetch(reason.meaning)}", "aria-hidden": true }),
        tag.span("#{reason.label}: ", class: "sr-only"),
        tag.span(reason.detail, class: "truncate")
      ])
    end
  end

  def outreach_reason_filter(key, count, current)
    meta = Outreach::Prospects::REASONS.fetch(key)
    lc_toggle_group_item(href: outreach_path(view: "people", reason: key), current: current, title: meta[:label]) do
      safe_join([
        lc_icon(meta[:icon], options: { class: "size-4", "aria-hidden": true }),
        tag.span(meta[:label]),
        tag.span(count, class: "tabular-nums opacity-70")
      ])
    end
  end
end
