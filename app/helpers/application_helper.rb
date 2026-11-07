module ApplicationHelper
  def microdollars(value)
    number_to_currency(value.to_i / 1_000_000.0, precision: 3)
  end

  def navigation_sections
    [
      [ "Work", [ [ "People", people_path, "users" ], [ "Compose", drafts_path, "pencil-square" ] ] ],
      [ "Relationships", [ [ "Network", network_path, "share" ], [ "Timeline", timeline_path, "queue-list" ], [ "Follow review", follow_reviews_path, "user-minus" ], [ "Followers", follower_history_path, "chart-bar" ] ] ],
      [ "Data", [ [ "X data", x_sources_path, "circle-stack" ], [ "Grok", grok_connector_path, "sparkles" ], [ "Spending", x_billing_cycles_path, "banknotes" ] ] ]
    ]
  end

  def navigation_active?(path)
    request.path.start_with?(path) || (path == people_path && current_page?(root_path))
  end

  def demo?
    Rails.configuration.x.demo
  end

  # Fills and text for the app's meaning colors (see tokens.css). Badges keep the library shape.
  MEANING_CLASSES = {
    you: "bg-you/15 text-you", both: "bg-success-soft text-success", them: "bg-warning-soft text-warning",
    like: "bg-like/15 text-like", message: "bg-message/15 text-message", grok: "bg-grok/15 text-grok",
    neutral: "bg-tile text-muted-foreground"
  }.freeze
  MEANING_TEXT = { you: "text-you", both: "text-success", them: "text-warning", like: "text-like",
    message: "text-message", grok: "text-grok", neutral: "text-muted-foreground" }.freeze

  # Two-way is green, only you is blue, only them is amber: the person reached out and you have not yet.
  def state_meaning(state)
    case state
    when "Two-way", "Mutual" then :both
    when "You replied only", "You follow", "You follow · follow-back unknown" then :you
    when "They replied only", "Follows you", "Observed follower" then :them
    else :neutral
    end
  end

  def meaning_badge(meaning, &block)
    lc_badge(class: MEANING_CLASSES.fetch(meaning), &block)
  end

  # A ring in the follow relationship's color: green both ways, blue you follow, amber they follow.
  RING_CLASSES = { both: "ring-success", you: "ring-you", them: "ring-warning" }.freeze

  def person_avatar(person, size: :md, ring: nil, **options)
    ring_class = RING_CLASSES[state_meaning(ring)] if ring
    options[:class] = [ options[:class], ("ring-2 ring-offset-2 ring-offset-card #{ring_class}" if ring_class) ].compact.join(" ").presence
    options.compact!
    if person.avatar_url.present? && !demo?
      lc_avatar(src: person.avatar_image_url, alt: "", size: size, loading: "lazy", referrerpolicy: "no-referrer", **options)
    else
      lc_avatar(person.initials, size: size, **options)
    end
  end

  def owner_avatar(size: :md)
    url = X::Connection.current&.avatar_image_url unless demo?
    url ? lc_avatar(src: url, alt: "", size: size, referrerpolicy: "no-referrer") : lc_avatar("You", size: size, class: "bg-you text-background")
  end

  # Each tag keeps one hue wherever it appears, so groups are easy to spot in lists.
  TAG_HUES = [
    "bg-sky-400/15 text-sky-300", "bg-emerald-400/15 text-emerald-300", "bg-amber-400/15 text-amber-300",
    "bg-rose-400/15 text-rose-300", "bg-violet-400/15 text-violet-300", "bg-cyan-400/15 text-cyan-300",
    "bg-lime-400/15 text-lime-300", "bg-orange-400/15 text-orange-300", "bg-fuchsia-400/15 text-fuchsia-300",
    "bg-indigo-400/15 text-indigo-300"
  ].freeze

  def tag_hue(name)
    TAG_HUES[Zlib.crc32(name.to_s) % TAG_HUES.size]
  end

  def tag_chip(name, href: people_path(tag: name), remove: nil)
    lc_badge(class: "#{tag_hue(name)} rounded-full") do
      safe_join([
        link_to("##{name}", href, class: "hover:underline"),
        (button_to(remove, method: :delete, class: "-me-1 inline-flex cursor-pointer rounded-full opacity-70 hover:opacity-100", aria: { label: "Remove #{name}" }, form: { class: "inline-flex" }) { lc_icon("x-mark", options: { class: "size-3", "aria-hidden": true }) } if remove)
      ].compact)
    end
  end

  def relationship_icon(state)
    case state
    when "Two-way", "Mutual" then "arrows-right-left"
    when "You replied only", "You follow", "You follow · follow-back unknown" then "arrow-up-right"
    when "They replied only", "Follows you", "Observed follower" then "arrow-down-left"
    when "No observed replies" then "chat-bubble-left-ellipsis"
    when "Neither" then "user"
    else "question-mark-circle"
    end
  end

  def grok_badge(label = "Grok")
    lc_badge(class: "bg-grok/15 text-grok") { safe_join([ lc_icon("sparkles", options: { class: "size-3.5", "aria-hidden": true }), label ]) }
  end

  def relationship_badge(state)
    meaning_badge(state_meaning(state)) do
      safe_join([lc_icon(relationship_icon(state), options: { class: "size-3.5", "aria-hidden": true }), tag.span(state)])
    end
  end

  def person_actions(person)
    safe_join([
      person.pin ? lc_button_to("Unpin", person_pin_path(person), method: :delete, variant: :ghost, size: :sm, icon: "bookmark-slash") : lc_button_to("Pin", person_pin_path(person), variant: :ghost, size: :sm, icon: "bookmark"),
      person.follow_protection ? lc_badge(tone: :success) { safe_join([lc_icon("shield-check", options: { class: "size-3.5", "aria-hidden": true }), "Keep following"]) } : nil
    ].compact, " ")
  end

  def source_link(label, url, **options)
    if demo?
      lc_button(label, disabled: true, variant: options.fetch(:variant, :secondary), size: :sm, title: "Fictional demo data has no live X link")
    else
      lc_button_link_to(label, url, target: "_blank", rel: "noopener noreferrer", icon: "arrow-up-right", **options)
    end
  end
end
