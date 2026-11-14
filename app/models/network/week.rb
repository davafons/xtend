# One week in review: what you did, what it brought, how your followers moved, your best reply and post, and what
# to do next. A week is the seven days ending today, or `weeks_ago` weeks before that. Each figure comes from saved
# data and says where it comes from; a source that wasn't collected for the week shows as missing, not zero.
class Network::Week
  MAX_WEEKS_AGO = 12

  attr_reader :weeks_ago, :starts_at, :ends_at

  def initialize(weeks_ago: 0, now: Time.current)
    @weeks_ago = weeks_ago.to_i.clamp(0, MAX_WEEKS_AGO)
    @ends_at = weeks_ago.to_i.zero? ? now : (now - @weeks_ago.weeks).end_of_day
    @starts_at = (@ends_at - 6.days).beginning_of_day
  end

  def range = starts_at..ends_at
  def current? = weeks_ago.zero?

  # What you did.
  def replies = ReplyEvent.where(direction: "outgoing", occurred_at: range)
  def new_targets = Outreach::Target.joins(:reply_event).where(reply_events: { occurred_at: range }).count
  def follow_ups = replies.where(classification: "continuation").count
  def people_count = ReplyEvent.where(occurred_at: range).distinct.count(:person_id)

  # What it brought: replies to you, and answers to this week's replies (later answers still count).
  def replies_to_you = ReplyEvent.where(direction: "incoming", occurred_at: range).count
  def answers = @answers ||= Network::AnswerRate.new(replies, coverage: X::MentionCoverage.new)
  # This week's replies answered by the same person within a week, among those seen so far.
  def answers_seen = replies.to_a.count { |reply| answers.answered?(reply) }
  # Whether a missing answer could just be uncollected: a reply outside mentions coverage, or still inside its week.
  def answers_incomplete? = answers.uncovered.any? || answers.open.positive?

  # X analytics for the week's days, when collected.
  def analytics_days = @analytics_days ||= X::AccountDay.between(starts_at.to_date, ends_at.to_date).to_a
  def analytics_totals = X::AccountDay.totals(analytics_days)

  # Complete follower checks inside the week: [gained, lost] summed, or nil without two checks.
  def follower_change
    changes = Follow::Snapshot.follower_changes(since: starts_at, before: ends_at).select { |_, gained| gained }
    [ changes.sum { _1[1] }, changes.sum { _1[2] } ] if changes.any?
  end

  # The reply that brought the most, by X analytics.
  def best_reply
    @best_reply ||= begin
      events = replies.includes(:person).to_a
      found = X::PostAnalytic.where(post_x_id: events.map(&:x_id)).index_by(&:post_x_id)
      events.filter_map { |event| (analytics = found[event.x_id]) && Network::XAnalytics::Reply.new(event, analytics) }
        .max_by { |reply| [ reply.follows, reply.visits, reply.impressions ] }
    end
  end

  # Your top-level post with the most impressions (X analytics) or views (captured counts).
  def best_post
    @best_post ||= begin
      owner = Current.workspace.owner_x_id
      analytics = X::PostAnalytic.where(published_at: range).where.not(post_x_id: ReplyEvent.select(:x_id)).to_a
        .reject { |post| post.body.to_s.start_with?("@") }.max_by { |post| post.metric("Impressions").to_i }
      captured = X::SourcePost.where(author_x_id: owner, repost: false, reply_to_x_id: nil, published_at: range)
        .where.not(view_count: nil).order(view_count: :desc).first
      if analytics then { x_id: analytics.post_x_id, body: analytics.body, count: analytics.metric("Impressions").to_i, label: "impressions", source: "X analytics" }
      elsif captured then { x_id: captured.x_id, body: captured.body, count: captured.view_count, label: "views", source: "counts seen #{captured.metrics_observed_at&.strftime('%-d %b')}" }
      end
    end
  end

  # What to do next, as of now.
  def reminders = Reminder.due.includes(:person).order(:due_on).limit(5)
  def waiting_count = ReplyInbox.new(days: 7).waiting_count
  def gone_quiet = Outreach::Prospects.new(reason: "quiet").to_a.first(5)
end
