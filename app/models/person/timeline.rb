class Person::Timeline
  include Enumerable

  # A post entry renders like a tweet: an author (:you or :them), its text, and the post it replied to
  # as a parent, when that text was collected. Other entries are compact events. Tones are the
  # app's meaning colors: :you, :both, :them, :like, :message, :ai, or :neutral.
  Entry = Data.define(:at, :category, :icon, :tone, :title, :kind, :author, :body, :parent, :x_id, :detail, :url) do
    def initialize(at:, category:, icon:, title:, tone: :neutral, kind: :event, author: nil, body: nil, parent: nil, x_id: nil, detail: nil, url: nil)
      super
    end

    def post? = kind == :post
  end
  Parent = Data.define(:author, :body, :x_id)

  CATEGORIES = { "conversation" => "Conversation", "messages" => "Direct messages", "engagement" => "Likes & bookmarks",
    "follows" => "Follows", "decisions" => "Your decisions" }.freeze

  attr_reader :person

  def initialize(person)
    @person = person
  end

  def each(&block)
    entries.each(&block)
  end

  # A like or bookmark on a post already shown, as an entry or as a reply's parent, marks that post
  # instead of repeating it.
  def entries
    @entries ||= begin
      shown = [*reply_entries, *post_entries, *authored_entries]
      shown_ids = shown.flat_map { |entry| [entry.x_id, entry.parent&.x_id] }.compact.to_set
      [*shown, *engagement_entries.reject { |entry| shown_ids.include?(entry.x_id) }, *message_entries,
        *follower_entries, *following_entries, *decision_entries].sort_by { |entry| -entry.at.to_f }
    end
  end

  # The counts X last showed for a post on this page, with when they were seen; nothing for a post never counted.
  def counts_for(x_id)
    source = counted_sources[x_id]
    return {} unless source&.metrics_observed_at
    { counts: { reply: source.reply_count, repost: source.repost_count, like: source.like_count, view: source.view_count, bookmark: source.bookmark_count },
      counts_note: "As seen on X #{source.metrics_observed_at.strftime(source.metrics_observed_at.year == Date.current.year ? '%-d %b, %H:%M' : '%-d %b %Y')}" }
  end

  # The saved posts behind this page's entries and their parents, for counts, media, and each post's page.
  def sources
    @sources ||= X::SourcePost.where(x_id: entries.select(&:post?).flat_map { |entry| [ entry.x_id, entry.parent&.x_id ] }.compact).index_by(&:x_id)
  end

  # X's private totals for your own posts and replies on this page, from its analytics Content page.
  def analytics_for(x_id)
    @analytics ||= X::PostAnalytic.where(post_x_id: entries.select(&:post?).flat_map { |entry| [ entry.x_id, entry.parent&.x_id ] }.compact).index_by(&:post_x_id)
    @analytics[x_id]
  end

  def filter(category)
    return entries unless category
    entries.select { |entry| entry.category == category || (category == "engagement" && marked?(entry)) }
  end

  # Posts that reply to each other form one thread, oldest first, so an exchange reads top to bottom
  # and no post appears twice. A thread sorts by its latest post.
  Thread = Data.define(:posts) do
    def at = posts.last.at
    def authors = posts.map(&:author).uniq
  end

  def items(category = nil)
    list = filter(category)
    posts = list.select { |entry| entry.post? && entry.x_id }.index_by(&:x_id)
    root = ->(entry) { (parent = posts[entry.parent&.x_id]) && parent != entry ? root.(parent) : entry }
    threads = posts.values.group_by { |entry| root.(entry) }.transform_values { |group| group.sort_by(&:at) }
    grouped = list.filter_map do |entry|
      next entry unless posts[entry.x_id].equal?(entry)
      group = threads.fetch(root.(entry))
      next unless group.last.equal?(entry)
      group.size > 1 ? Thread.new(posts: group) : entry
    end
    grouped.sort_by { |item| -item.at.to_f }
  end

  def counts
    counts = entries.group_by(&:category).transform_values(&:size)
    counts["engagement"] = entries.count { |entry| entry.category == "engagement" || marked?(entry) } if person.engagements.any?
    counts
  end

  # The owner's likes and bookmarks by post ID, e.g. { "90" => ["like"] }.
  def marks
    @marks ||= person.engagements.group_by(&:post_x_id).transform_values { |list| list.map(&:kind).uniq }
  end

  def marked?(entry)
    marks.key?(entry.x_id) || marks.key?(entry.parent&.x_id)
  end

  private

  def reply_entries
    events = person.reply_events.to_a
    sources = X::SourcePost.where(x_id: events.flat_map { |event| [event.x_id, event.target_x_id] }).index_by(&:x_id)
    events.map do |event|
      outgoing = event.direction == "outgoing"
      title = outgoing ? "You replied to #{person.name}" : "#{person.name} replied to you"
      title += " | follow-up" if event.classification == "continuation"
      parent_body = text(sources[event.target_x_id]&.body)
      Entry.new(at: event.occurred_at, category: "conversation", kind: :post, author: outgoing ? :you : :them,
        icon: outgoing ? "arrow-up-right" : "arrow-down-left", tone: outgoing ? :you : :both, title: title,
        body: text(sources[event.x_id]&.body), x_id: event.x_id,
        parent: Parent.new(author: outgoing ? :them : :you, body: parent_body, x_id: event.target_x_id),
        detail: event.source == "demo" ? "Fictional demo evidence" : "Confirmed via #{event.source == 'x_api' ? 'the X API' : 'your X archive'}",
        url: event.source == "demo" ? nil : status_url(event.x_id))
    end
  end

  def post_entries
    person.outreach_candidates.map do |post|
      Entry.new(at: post.published_at, category: "conversation", kind: :post, author: :them, icon: "sparkles",
        tone: post.source == "ai" ? :ai : :neutral, title: "Posted | suggested for outreach", body: text(post.body), x_id: post.x_id,
        detail: post.match_reason, url: post.source_url)
    end
  end

  def authored_entries
    return [] if person.x_id.blank?
    # Posts you replied to already appear above your reply.
    known = person.reply_events.flat_map { |event| [event.x_id, event.target_x_id] } + person.outreach_candidates.map(&:x_id)
    X::SourcePost.where(author_x_id: person.x_id, repost: false).where.not(x_id: known).map do |source|
      Entry.new(at: source.published_at, category: "conversation", kind: :post, author: :them, icon: "chat-bubble-bottom-center-text",
        title: source.parent_x_id ? "Replied in a thread" : "Posted", body: text(source.body), x_id: source.x_id, url: status_url(source.x_id))
    end
  end

  def message_entries
    person.direct_messages.order(:occurred_at).group_by { |message| message.occurred_at.to_date }.map do |_, messages|
      sent, received = messages.partition { |message| message.direction == "outgoing" }
      last = messages.last
      counts = [("#{sent.size} from you" if sent.any?), ("#{received.size} from them" if received.any?)].compact.join(", ")
      Entry.new(at: last.occurred_at, category: "messages", icon: "envelope", tone: :message,
        title: "Direct messages | #{counts}", detail: "Last from #{last.direction == 'outgoing' ? 'you' : 'them'}. Message text is not stored.")
    end
  end

  def counted_sources
    @counted_sources ||= sources.select { |_, source| source.metrics_observed_at }
  end

  def engagement_entries
    person.engagements.map do |engagement|
      like = engagement.kind == "like"
      detail = if engagement.observed_after
        "#{like ? 'Liked' : 'Bookmarked'} between #{engagement.observed_after.strftime('%-d %b')} and #{engagement.observed_at.strftime('%-d %b %Y')}"
      else
        "Post from #{engagement.post_published_at.strftime('%-d %b %Y')}. X doesn't report when you #{like ? 'liked' : 'bookmarked'} it."
      end
      Entry.new(at: engagement.earliest_at, category: "engagement", kind: :post, author: :them, icon: like ? "heart" : "bookmark",
        tone: like ? :like : :you, title: like ? "You liked their post" : "You bookmarked their post", body: text(engagement.body),
        x_id: engagement.post_x_id, detail: detail, url: status_url(engagement.post_x_id))
    end
  end

  # Complete follower lists bound when a follow started; a "followed you" notification on X dates it exactly.
  def follower_entries
    followed_at = followed_you_at
    dated = nil
    entries = person.follower_periods.flat_map do |period|
      notified = followed_at && followed_at <= period.first_seen_at && (period.baseline? || followed_at >= period.followed_after)
      dated = period if notified
      started = if notified
        Entry.new(at: followed_at, category: "follows", icon: "user-plus", tone: :both, title: "Started following you",
          detail: "On #{followed_at.strftime('%-d %b %Y')}, from your X notifications")
      elsif period.baseline?
        Entry.new(at: period.first_seen_at, category: "follows", icon: "arrow-down-left", tone: :both,
          title: "Already following you at the first complete follower check",
          detail: "The start date is unknown. A baseline check cannot show when they followed.")
      else
        Entry.new(at: period.first_seen_at, category: "follows", icon: "user-plus", tone: :both, title: "Started following you",
          detail: "Between #{period.followed_after.strftime('%-d %b %Y')} and #{period.first_seen_at.strftime('%-d %b %Y')}")
      end
      ended = if period.ended_by
        Entry.new(at: period.ended_by, category: "follows", icon: "user-minus", tone: :them, title: "No longer following you",
          detail: "Last seen #{period.last_seen_at.strftime('%-d %b %Y')}; missing from the complete check on #{period.ended_by.strftime('%-d %b %Y')}")
      end
      [started, ended].compact
    end
    if followed_at && !dated
      entries << Entry.new(at: followed_at, category: "follows", icon: "user-plus", tone: :both, title: "Followed you",
        detail: "From your X notifications. Follow checks show whether they still do.")
    end
    entries
  end

  def followed_you_at
    owner = Current.workspace.owner_x_id
    X::FollowEdge.where(follower_x_id: person.x_id, followed_x_id: owner).pick(:followed_at) if person.x_id && owner
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
          Entry.new(at: snapshot.observed_at, category: "follows", icon: "arrow-up-right", tone: :you,
            title: "You were following them at the first complete following check", detail: "The start date is unknown.")
        else
          Entry.new(at: snapshot.observed_at, category: "follows", icon: "user-plus", tone: :you, title: "You started following them",
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
    labels = { "keep" => "You chose to keep following", "defer" => "You deferred the follow review", "reported_unfollow" => "You reported unfollowing on X", "unfollowed" => "You unfollowed on X" }
    reviews = person.follow_reviews.map do |review|
      Entry.new(at: review.updated_at, category: "decisions", icon: { "keep" => "shield-check", "defer" => "clock", "reported_unfollow" => "user-minus", "unfollowed" => "user-minus" }.fetch(review.decision),
        tone: review.decision == "keep" ? :both : :neutral, title: labels.fetch(review.decision),
        detail: { "reported_unfollow" => "X status is unchanged until the capture or a following check confirms it.",
          "unfollowed" => "Seen by the browser capture." }[review.decision])
    end
    [
      Entry.new(at: person.created_at, category: "decisions", icon: "user", title: "Added to Xtend"),
      (Entry.new(at: person.pin.created_at, category: "decisions", icon: "bookmark", tone: :you, title: "You pinned them") if person.pin),
      (Entry.new(at: person.follow_protection.created_at, category: "decisions", icon: "shield-check", tone: :both, title: "Protected from cleanup") if person.follow_protection),
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
