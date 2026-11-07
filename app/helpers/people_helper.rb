module PeopleHelper
  FILTER_KEYS = %i[q state follow filter tag sort].freeze

  def people_filter_params(**changes)
    params.permit(*FILTER_KEYS).to_h.symbolize_keys.merge(changes).compact_blank
  end

  def people_sort_header(label, sort, align: nil)
    active = @sort == sort
    link_to people_path(people_filter_params(sort: sort)), class: [ "inline-flex items-center gap-tight hover:text-primary", ("text-primary" if active), align ], aria: { sort: (active ? "descending" : nil) } do
      safe_join([ label, (lc_icon("chevron-down", options: { class: "size-3.5", "aria-hidden": true }) if active) ].compact)
    end
  end

  def compact_count(value)
    return "—" unless value
    number_to_human(value, precision: 3, significant: true, format: "%n%u", units: { thousand: "K", million: "M", billion: "B" })
  end

  def relative_day(time)
    return tag.span("—", class: "text-muted-foreground") unless time
    tag.time("#{time_ago_in_words(time)} ago", datetime: time.iso8601, title: time.strftime("%-d %B %Y, %H:%M"))
  end

  def interaction_label(signal)
    return "No interaction observed in collected history" unless signal
    day = signal.at.strftime(signal.at.year == Date.current.year ? "%-d %b" : "%-d %b %Y")
    case [signal.channel, signal.direction]
    in ["reply", "outgoing"] then "You replied · #{day}"
    in ["reply", "incoming"] then "They replied to you · #{day}"
    in ["mention", _] then "They mentioned you · #{day}"
    in ["dm", "outgoing"] then "You messaged them · #{day}"
    in ["dm", "incoming"] then "They messaged you · #{day}"
    in ["like", "incoming"] then "They liked your post · seen #{day}"
    in ["like", _] then "You liked their post · on or after #{day}"
    in ["repost", "outgoing"] then "You reposted them · seen #{day}"
    in ["repost", "incoming"] then "They reposted you · seen #{day}"
    in ["quote", "outgoing"] then "You quoted them · #{day}"
    in ["quote", "incoming"] then "They quoted you · #{day}"
    in ["bookmark", _] then "You bookmarked their post · on or after #{day}"
    end
  end
end
