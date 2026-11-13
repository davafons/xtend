# X's own analytics for your account over an Insights period, from the analytics pages the capture extension saw:
# impressions per bucket, totals the way X's Overview page sums them, and the posts with private totals. Only
# covered days count; a bucket without any stays a gap.
class Network::XAnalytics
  POST_LIMIT = 8

  def initialize(activity)
    @activity = activity
    @from = activity.starts_at.to_date
    @to = activity.ends_at.to_date
  end

  def days
    @days ||= X::AccountDay.between(@from, @to).order(:day).to_a
  end

  def any? = days.any? || posts.any?
  def covered_days = days.size
  def period_days = (@to - @from).to_i + 1
  def observed_at = [ days.map(&:observed_at).max, posts.map(&:observed_at).max ].compact.max
  def totals = @totals ||= X::AccountDay.totals(days)

  def engagement_rate
    totals[:engagements].fdiv(totals[:impressions]) if totals[:impressions].positive?
  end

  # Impressions per Insights bucket; nil where no day in the bucket was collected.
  def per_bucket(metric = :impressions)
    grouped = days.group_by { |day| @activity.bucket_for(day.day.in_time_zone) }
    @activity.buckets.map { |bucket| grouped[bucket]&.sum { |day| day.count(metric) } }
  end

  def posts
    @posts ||= X::PostAnalytic.where(published_at: @activity.starts_at..@activity.ends_at).to_a
      .sort_by { |post| -post.metric("Impressions").to_i }.first(POST_LIMIT)
  end
end
