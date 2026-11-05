class Person::Timeline
  include Enumerable

  Entry = Data.define(:at, :category, :icon, :tone, :title, :body, :context, :detail, :url) do
    def initialize(at:, category:, icon:, title:, tone: :neutral, body: nil, context: nil, detail: nil, url: nil)
      super
    end
  end

  CATEGORIES = { "conversation" => "Conversation", "messages" => "Direct messages", "engagement" => "Likes & bookmarks",
    "follows" => "Follows", "decisions" => "Your decisions" }.freeze

  attr_reader :person

  def initialize(person)
    @person = person
  end

  def each(&block)
    entries.each(&block)
  end

  def entries
    @entries ||= [*reply_entries, *post_entries, *authored_entries, *message_entries, *engagement_entries, *follower_entries, *following_entries, *decision_entries]
      .sort_by { |entry| -entry.at.to_f }
  end

  def counts
    entries.group_by(&:category).transform_values(&:size)
  end

  private

  def reply_entries
    events = person.reply_events.to_a
    sources = X::SourcePost.where(x_id: events.flat_map { |event| [event.x_id, event.target_x_id] }).index_by(&:x_id)
    events.map do |event|
      outgoing = event.direction == "outgoing"
      title = outgoing ? "You replied to #{person.name}" : "#{person.name} replied to you"
      title += " · follow-up" if event.classification == "continuation"
      Entry.new(at: event.occurred_at, category: "conversation", icon: outgoing ? "arrow-up-right" : "arrow-down-left",
        tone: outgoing ? :primary : :success, title: title, body: text(sources[event.x_id]&.body),
        context: text(sources[event.target_x_id]&.body).then { |body| body && "#{outgoing ? 'Their' : 'Your'} post: #{body}" },
        detail: event.source == "demo" ? "Fictional demo evidence" : "Confirmed via #{event.source == 'x_api' ? 'the X API' : 'your X archive'}",
        url: event.source == "demo" ? nil : status_url(event.x_id))
    end
  end

  def post_entries
    person.posts.includes(:post_disposition, :reply_report).flat_map do |post|
      entries = [Entry.new(at: post.published_at, category: "conversation", icon: "sparkles", title: "Posted · suggested in Today",
        body: text(post.body), detail: post.match_reason, url: post.source_url)]
      if (disposition = post.post_disposition)
        entries << Entry.new(at: disposition.updated_at, category: "decisions", icon: disposition.kind == "skipped" ? "forward" : "clock",
          title: disposition.kind == "skipped" ? "You skipped this post" : "You snoozed this post",
          detail: disposition.until_at && "Until #{disposition.until_at.strftime('%-d %b, %H:%M')}")
      end
      if (report = post.reply_report)
        entries << Entry.new(at: report.created_at, category: "decisions", icon: "flag", tone: :warning,
          title: "You reported replying · waiting for confirmation", url: report.reply_url.presence)
      end
      entries
    end
  end

  def authored_entries
    return [] if person.x_id.blank?
    known = person.reply_events.map(&:x_id) + person.posts.map(&:x_id)
    X::SourcePost.where(author_x_id: person.x_id, repost: false).where.not(x_id: known).map do |source|
      Entry.new(at: source.published_at, category: "conversation", icon: "chat-bubble-bottom-center-text",
        title: source.parent_x_id ? "Replied in a thread" : "Posted", body: text(source.body), url: status_url(source.x_id))
    end
  end

  def message_entries
    person.direct_messages.order(:occurred_at).group_by { |message| message.occurred_at.to_date }.map do |_, messages|
      sent, received = messages.partition { |message| message.direction == "outgoing" }
      last = messages.last
      counts = [("#{sent.size} from you" if sent.any?), ("#{received.size} from them" if received.any?)].compact.join(", ")
      Entry.new(at: last.occurred_at, category: "messages", icon: "envelope", tone: last.direction == "outgoing" ? :primary : :success,
        title: "Direct messages · #{counts}", detail: "Last from #{last.direction == 'outgoing' ? 'you' : 'them'}. Message text is not stored.")
    end
  end

  def engagement_entries
    person.engagements.map do |engagement|
      like = engagement.kind == "like"
      detail = if engagement.observed_after
        "#{like ? 'Liked' : 'Bookmarked'} between #{engagement.observed_after.strftime('%-d %b')} and #{engagement.observed_at.strftime('%-d %b %Y')}"
      else
        "Post from #{engagement.post_published_at.strftime('%-d %b %Y')}. X doesn't report when you #{like ? 'liked' : 'bookmarked'} it."
      end
      Entry.new(at: engagement.earliest_at, category: "engagement", icon: like ? "heart" : "bookmark", tone: :primary,
        title: like ? "You liked their post" : "You bookmarked their post", body: text(engagement.body), detail: detail,
        url: status_url(engagement.post_x_id))
    end
  end

  def follower_entries
    person.follower_periods.flat_map do |period|
      started = if period.baseline?
        Entry.new(at: period.first_seen_at, category: "follows", icon: "arrow-down-left", tone: :success,
          title: "Already following you at the first complete follower check",
          detail: "The start date is unknown. A baseline check cannot show when they followed.")
      else
        Entry.new(at: period.first_seen_at, category: "follows", icon: "user-plus", tone: :success, title: "Started following you",
          detail: "Between #{period.followed_after.strftime('%-d %b %Y')} and #{period.first_seen_at.strftime('%-d %b %Y')}")
      end
      ended = if period.ended_by
        Entry.new(at: period.ended_by, category: "follows", icon: "user-minus", tone: :warning, title: "No longer following you",
          detail: "Last seen #{period.last_seen_at.strftime('%-d %b %Y')}; missing from the complete check on #{period.ended_by.strftime('%-d %b %Y')}")
      end
      [started, ended].compact
    end
  end

  def following_entries
    snapshots = Follow::Snapshot.where(direction: "following").where.not(completed_at: nil).order(:observed_at).to_a
    return [] if snapshots.empty?
    member_ids = person.follow_memberships.where(follow_snapshot_id: snapshots.map(&:id)).pluck(:follow_snapshot_id).to_set
    entries = []
    snapshots.each_with_index do |snapshot, index|
      member = member_ids.include?(snapshot.id)
      before = index.positive? && member_ids.include?(snapshots[index - 1].id)
      if member && !before
        entries << if index.zero?
          Entry.new(at: snapshot.observed_at, category: "follows", icon: "arrow-up-right", tone: :primary,
            title: "You were following them at the first complete following check", detail: "The start date is unknown.")
        else
          Entry.new(at: snapshot.observed_at, category: "follows", icon: "user-plus", tone: :primary, title: "You started following them",
            detail: "Between #{snapshots[index - 1].observed_at.strftime('%-d %b %Y')} and #{snapshot.observed_at.strftime('%-d %b %Y')}")
        end
      elsif !member && before
        entries << Entry.new(at: snapshot.observed_at, category: "follows", icon: "user-minus", title: "No longer in your following list",
          detail: "Missing from the complete check on #{snapshot.observed_at.strftime('%-d %b %Y')}")
      end
    end
    entries
  end

  def decision_entries
    labels = { "keep" => "You chose to keep following", "defer" => "You deferred the follow review", "reported_unfollow" => "You reported unfollowing on X" }
    reviews = person.follow_reviews.map do |review|
      Entry.new(at: review.updated_at, category: "decisions", icon: { "keep" => "shield-check", "defer" => "clock", "reported_unfollow" => "user-minus" }.fetch(review.decision),
        tone: review.decision == "keep" ? :success : :neutral, title: labels.fetch(review.decision),
        detail: ("X status is unchanged until a later following check confirms it." if review.decision == "reported_unfollow"))
    end
    [
      Entry.new(at: person.created_at, category: "decisions", icon: "user", title: "Added to your CRM"),
      (Entry.new(at: person.pin.created_at, category: "decisions", icon: "bookmark", tone: :primary, title: "You pinned them") if person.pin),
      (Entry.new(at: person.follow_protection.created_at, category: "decisions", icon: "shield-check", tone: :success, title: "Protected from cleanup") if person.follow_protection),
      *reviews
    ].compact
  end

  def text(body)
    CGI.unescapeHTML(body) if body
  end

  def status_url(x_id)
    "https://x.com/i/status/#{x_id}"
  end
end
