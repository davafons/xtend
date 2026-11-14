# X's own analytics for your account over an Insights period, from the analytics pages the capture extension saw:
# impressions per bucket, totals the way X's Overview page sums them, your posts' and replies' private totals,
# when your audience is active by weekday and hour, and who you reached. Only covered days and hours count; a
# bucket without any stays a gap.
class Network::XAnalytics
  POST_LIMIT = 8
  HEAT_LABELS = { "Impressions" => "Impressions", "Likes" => "Likes", "Replies" => "Replies", "Retweets" => "Reposts",
    "Bookmark" => "Bookmarks", "Share" => "Shares", "Follows" => "Follows", "ProfileVisits" => "Profile visits" }.freeze

  def initialize(activity)
    @activity = activity
    @from = activity.starts_at.to_date
    @to = activity.ends_at.to_date
  end

  def days
    @days ||= X::AccountDay.between(@from, @to).order(:day).to_a
  end

  def any? = days.any? || posts.any? || replies.any? || heat_metrics.any? || audience.present?
  def covered_days = days.size
  def period_days = (@to - @from).to_i + 1
  def observed_at = [ days.map(&:observed_at).max, posts.map(&:observed_at).max, audience&.observed_at ].compact.max
  def totals = @totals ||= X::AccountDay.totals(days)

  def engagement_rate
    totals[:engagements].fdiv(totals[:impressions]) if totals[:impressions].positive?
  end

  # Impressions per Insights bucket; nil where no day in the bucket was collected.
  def per_bucket(metric = :impressions)
    grouped = days.group_by { |day| @activity.bucket_for(day.day.in_time_zone) }
    @activity.buckets.map { |bucket| grouped[bucket]&.sum { |day| day.count(metric) } }
  end

  # Your top-level posts; replies are judged on their own below.
  def posts
    @posts ||= X::PostAnalytic.where(published_at: @activity.starts_at..@activity.ends_at)
      .where.not(post_x_id: ReplyEvent.where(direction: "outgoing").select(:x_id)).to_a
      .sort_by { |post| -post.metric("Impressions").to_i }.first(POST_LIMIT)
  end

  Reply = Data.define(:event, :analytics) do
    def visits = analytics.metric("ProfileVisits").to_i
    def follows = analytics.metric("Follows").to_i
    def impressions = analytics.metric("Impressions").to_i
  end

  # Your replies in the period that X's Content page counted, with the person each answered.
  def replies
    @replies ||= begin
      events = ReplyEvent.where(direction: "outgoing", occurred_at: @activity.starts_at..@activity.ends_at).includes(:person).to_a
      found = X::PostAnalytic.where(post_x_id: events.map(&:x_id)).index_by(&:post_x_id)
      events.filter_map { |event| (analytics = found[event.x_id]) && Reply.new(event, analytics) }
    end
  end

  def outgoing_reply_count
    ReplyEvent.where(direction: "outgoing", occurred_at: @activity.starts_at..@activity.ends_at).count
  end

  # Replies that brought people to your profile or to follow you first, then the most seen.
  def best_replies(limit = POST_LIMIT)
    replies.sort_by { |reply| [ -reply.follows, -reply.visits, -reply.impressions ] }.first(limit)
  end

  # Median impressions of counted replies posted in your audience's busy hours against the rest, when each side has
  # at least MINIMUM replies: { busy: [median, count], other: [median, count] } or nil.
  def reply_timing(hours = Network::ActiveHours.new)
    return unless hours.collected?
    busy, other = replies.partition { |reply| hours.level(reply.event.occurred_at) == :busy }
    return if busy.size < Outreach::Payoff::MINIMUM || other.size < Outreach::Payoff::MINIMUM
    median = ->(group) { group.map(&:impressions).sort.then { |values| (values[(values.size - 1) / 2] + values[values.size / 2]) / 2.0 } }
    { busy: [ median.(busy), busy.size ], other: [ median.(other), other.size ] }
  end

  def reply_totals
    { impressions: replies.sum(&:impressions), visits: replies.sum(&:visits), follows: replies.sum(&:follows) }
  end

  # The heatmap metrics collected for this period, and the chosen one's totals by weekday and hour in your time zone.
  def heat_metrics
    @heat_metrics ||= X::AnalyticsHour.where(hour: @activity.starts_at..@activity.ends_at).distinct.pluck(:metric)
      .sort_by { |metric| X::AnalyticsHour::METRICS.index(metric) }
  end

  # { [wday (0 = Monday), hour] => total } and how many weeks the hours span.
  def heat(metric)
    rows = X::AnalyticsHour.where(metric: metric, hour: @activity.starts_at..@activity.ends_at).pluck(:hour, :value)
    grid = Hash.new(0)
    rows.each { |hour, value| local = hour.in_time_zone; grid[[ (local.wday - 1) % 7, local.hour ]] += value }
    span = rows.empty? ? nil : rows.map(&:first).minmax
    [ grid, span ]
  end

  # Who saw you: the newest Audience snapshot whose range overlaps the period.
  def audience
    @audience ||= X::AnalyticsSnapshot.where(kind: "audience").where(to_on: @from..).where(from_on: ..@to).order(:observed_at).last
  end

  def account
    @account ||= X::AnalyticsSnapshot.latest("account")
  end
end
