module FollowHelper
  # Your own Followers or Following page on x.com, where scrolling to the end refreshes the list for free.
  def own_list_url(direction)
    handle = X::Connection.current&.username unless demo?
    handle ? "https://x.com/#{handle}/#{direction}" : nil
  end

  # One line on where a follow list stands: the latest complete one and any scroll in progress.
  def follow_list_summary(direction)
    complete = Follow::Snapshot.latest_complete(direction)
    scrolling = Follow::Snapshot.capturing(direction)
    parts = []
    if complete
      parts << "#{pluralize(complete.person_ids.size, "account")} · #{complete.observed_at.strftime('%-d %b, %H:%M')} · #{complete.captured? ? 'scrolled on x.com' : complete.source.humanize}"
    else
      parts << "No complete list yet"
    end
    if scrolling
      count = scrolling.follow_memberships.count
      parts << "scrolling now: #{count}#{" of #{scrolling.expected_count}" if scrolling.expected_count} seen"
    end
    parts.join(" · ")
  end

  CAPTURE_LABELS = { "posts" => "post", "people_added" => "new person", "likes" => "like", "bookmarks" => "bookmark",
    "interactions" => "interaction", "relationships" => "follow state", "unfollows" => "unfollow" }.freeze

  # What the latest extension batch added, in a few words: "12 posts · following list 300 of 511".
  def capture_summary(summary)
    return if summary.blank?
    parts = CAPTURE_LABELS.filter_map { |key, word| pluralize(summary[key], word, plural: (word == "new person" ? "new people" : nil)) if summary[key].to_i.positive? }
    lists = Array(summary["lists"]).map do |list|
      name = "#{list["direction"]} list"
      case list["state"]
      when "completed" then "#{name} complete: #{list["seen"]}"
      when "short" then "#{name} ended at #{list["seen"]} of #{list["expected"]}: scroll it again"
      else "#{name} #{list["seen"]}#{" of #{list["expected"]}" if list["expected"]} so far"
      end
    end
    (lists + parts).first(4).join(" · ").presence
  end
end
