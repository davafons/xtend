module PeopleHelper
  FILTER_KEYS = %i[q state follow filter tag list from to sort].freeze

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
    in ["reply", "outgoing"] then "You replied | #{day}"
    in ["reply", "incoming"] then "They replied to you | #{day}"
    in ["mention", _] then "They mentioned you | #{day}"
    in ["dm", "outgoing"] then "You messaged them | #{day}"
    in ["dm", "incoming"] then "They messaged you | #{day}"
    in ["like", "incoming"] then "They liked your post | seen #{day}"
    in ["like", _] then "You liked their post | on or after #{day}"
    in ["repost", "outgoing"] then "You reposted them | seen #{day}"
    in ["repost", "incoming"] then "They reposted you | seen #{day}"
    in ["quote", "outgoing"] then "You quoted them | #{day}"
    in ["quote", "incoming"] then "They quoted you | #{day}"
    in ["bookmark", _] then "You bookmarked their post | on or after #{day}"
    end
  end

  # A relationship as one colored icon; the state is its title and screen-reader text.
  def relationship_cue(state, title: state)
    meaning = state_meaning(state)
    tag.span(class: "inline-flex #{ApplicationHelper::MEANING_TEXT.fetch(meaning)}", title: title) do
      safe_join([ lc_icon(relationship_icon(state), options: { class: "size-4", "aria-hidden": true }), tag.span(state, class: "sr-only") ])
    end
  end

  # Replies in a table cell: replies from you (blue) | from them; the reply state is the title.
  def reply_counts(person)
    return tag.span("—", class: "text-muted-foreground", title: "No observed replies") if person.reply_events.empty?
    title = "#{person.reply_state}: #{person.outgoing_count} from you, #{person.incoming_count} from them"
    tag.span(class: "inline-flex items-center gap-related tabular-nums", title: title) do
      safe_join([ tag.span(person.reply_state, class: "sr-only"), tag.span(person.outgoing_count, class: "text-you"),
        tag.span("|", class: "text-muted-foreground", "aria-hidden": true), tag.span(person.incoming_count) ])
    end
  end

  # Pin and keep-following as round icon buttons, like the buttons on an X profile.
  def person_profile_actions(person)
    pin = if person.pin
      lc_icon_button_to("Unpin", person_pin_path(person), method: :delete, variant: :outline, title: "Pinned | unpin", aria: { pressed: true }) { lc_icon("bookmark", variant: :solid, options: { class: "text-you", "aria-hidden": true }) }
    else
      lc_icon_button_to("Pin", person_pin_path(person), icon: "bookmark", variant: :outline, title: "Pin")
    end
    keep = if person.follow_protection
      lc_icon_button_to("Remove manual protection", person_follow_protection_path(person), method: :delete, variant: :outline, title: "Kept: protected from cleanup | remove", aria: { pressed: true }) { lc_icon("shield-check", variant: :solid, options: { class: "text-success", "aria-hidden": true }) }
    else
      lc_icon_button_to("Keep following", person_follow_protection_path(person), icon: "shield-check", variant: :outline, title: "Keep following: protect from cleanup (mutuals are protected automatically)")
    end
    safe_join([ pin, keep ])
  end

  # A link to a person that previews them on hover: their card loads the first time it opens.
  # Pass the link text, or a block for richer content such as an avatar and name.
  def person_link(person, name = nil, **options, &block)
    lc_hovercard(src: person_card_path(person), class: options.delete(:wrapper_class)) do |card|
      attributes = options.merge(data: (options[:data] || {}).merge(card[:data]))
      block ? link_to(person, **attributes, &block) : link_to(name || person.name, person, **attributes)
    end
  end

  # The ways to look at your people: the table, who's due, the board, and your lists.
  def people_views(current)
    view_tabs "People views", [
      [ "All people", people_path, current == :table ],
      [ "Tend", people_tend_path, current == :tend ],
      [ "Board", people_board_path, current == :board ],
      [ "Lists", lists_path, current == :lists ]
    ]
  end

  def tier_badge(list)
    return unless list&.tier?
    lc_badge(list.name, shape: :pill, class: list.tier == "getting_to_know" ? "bg-tile text-muted-foreground" : "bg-primary/15 text-primary")
  end

  # "Due 4 days ago", "Due today", "In 3 days", or "Never replied".
  def due_label(item)
    return "Never replied" unless item.last_reply_at
    return "In #{pluralize(item.due_in, 'day')}" unless item.due?
    overdue = item.days_since - item.cadence_days
    overdue.zero? ? "Due today" : "#{pluralize(overdue, 'day')} overdue"
  end

  # Buttons to place a person on a tier: the current one is pressed and takes them off it; the others move them there.
  def tier_buttons(person, size: :sm)
    current = person.tier_list
    tag.div(class: "flex flex-wrap gap-tight", role: "group", aria: { label: "Tier for #{person.name}" }) do
      safe_join((@_tiers ||= List.tiers.to_a).reverse.map do |list|
        on = current&.id == list.id
        button_to(list.name, on ? list_membership_path(list, person) : list_memberships_path(list),
          method: on ? :delete : :post, params: (on ? {} : { person_id: person.id }), form: { class: "contents" },
          class: lc_toggle_class(active: on, size: size), aria: { pressed: on }, title: on ? "Take them off #{list.name}" : "Move them to #{list.name}")
      end)
    end
  end
end
