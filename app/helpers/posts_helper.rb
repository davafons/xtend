module PostsHelper
  ICON_BOX = "inline-flex size-8 items-center justify-center rounded-full".freeze

  # One count in a post's action row, drawn as X does: an icon, then the number when above zero. Your own like or
  # bookmark fills the icon in its color. With counted: false only your marks show; a count the capture didn't
  # collect shows a faint icon that says so on hover.
  def x_post_stat(icon, count, label, counted: true, mine: false, tone: nil, note: nil)
    return if !mine && !counted
    title = if mine then "You #{label.delete_suffix('s').sub(/e?\z/, 'ed')} this"
    elsif count.nil? then "#{label.capitalize} not collected"
    else [ "#{number_with_delimiter(count)} #{label}", note ].compact.join(" · ")
    end
    tag.span(class: [ "inline-flex items-center", (tone if mine), ("opacity-40" if count.nil? && !mine) ], title: title) do
      safe_join([
        tag.span(lc_icon(icon, variant: (mine ? :solid : :outline), options: { class: "size-[1.15rem]", "aria-hidden": true }), class: ICON_BOX),
        tag.span(title, class: "sr-only"),
        (compact_count(count) if count.to_i.positive?)
      ].compact)
    end
  end

  # X's own timestamps: "now", "12m", "4h" within a day, then "4 Nov", and "4 Nov 2025" in earlier years.
  def x_post_time(at, detail: nil)
    label =
      if at > 1.minute.ago then "now"
      elsif at > 1.hour.ago then "#{((Time.current - at) / 60).floor}m"
      elsif at > 1.day.ago then "#{((Time.current - at) / 3600).floor}h"
      else at.strftime(at.year == Time.current.year ? "%-d %b" : "%-d %b %Y")
      end
    tag.time(label, datetime: at.iso8601, title: [ at.strftime("%-d %B %Y, %H:%M"), detail ].compact.join(" · "))
  end

  # Post text with line breaks kept and links, @mentions and #hashtags in the link color, as X shows them.
  def x_post_body(text)
    parts = text.to_s.split(%r{(https?://\S+|(?<![\w@])@\w{1,15}|(?<![\w#])#[A-Za-z_]\w*)})
    safe_join(parts.map.with_index do |part, index|
      if index.odd? && part.start_with?("http")
        link_to(part.sub(%r{\Ahttps?://(www\.)?}, "").truncate(32), part, target: "_blank", rel: "noopener noreferrer", class: "text-you hover:underline")
      elsif index.odd?
        tag.span(part, class: "text-you")
      else
        part
      end
    end)
  end
end
