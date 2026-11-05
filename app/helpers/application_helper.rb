module ApplicationHelper
  def microdollars(value)
    number_to_currency(value.to_i / 1_000_000.0, precision: 3)
  end

  def demo?
    Rails.configuration.x.demo
  end

  def state_tone(state)
    case state
    when "Two-way", "Mutual" then :success
    when "You replied only", "They replied only" then :primary
    else :neutral
    end
  end

  def person_avatar(person, size: :base)
    tone = %w[blue green orange sand][person.id.to_i % 4]
    if person.avatar_url.present? && !demo?
      lc_avatar(src: person.avatar_image_url, alt: "", size: size, class: "crm-avatar", loading: "lazy", referrerpolicy: "no-referrer", data: { avatar_tone: tone })
    else
      lc_avatar(person.initials, size: size, class: "crm-avatar", data: { avatar_tone: tone })
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

  def relationship_badge(state)
    lc_badge(tone: state_tone(state)) do
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
