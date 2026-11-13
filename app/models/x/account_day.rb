# One day of X's own account analytics, as the analytics Overview page on x.com loaded it: how many times each
# kind of engagement happened, split by whether the engaging account was verified. A day is saved only when the
# captured range covered it and X had already counted it, so a missing day means not collected, never zero.
class X::AccountDay < ApplicationRecord
  include WorkspaceScoped
  self.table_name = "x_account_days"

  # X's labels, as its Overview page totals them (checked against the page): reposts include quotes, and
  # engagements are the sum of the others.
  METRICS = {
    impressions: %w[Displayed], profile_visits: %w[ProfilePic], likes: %w[Fav], replies: %w[Reply],
    reposts: %w[Retweet QuoteTweet], bookmarks: %w[Bookmark], shares: %w[Share], follows: %w[Follow], unfollows: %w[Unfollow],
    video_views: %w[VideoViews], media_views: %w[MediaViews]
  }.freeze
  ENGAGEMENTS = %i[profile_visits likes replies reposts bookmarks shares].freeze

  scope :between, ->(from, to) { where(day: from..to) }

  # Saves each day unless a newer sighting of it is already saved.
  def self.record!(days, at:)
    days.each do |day, counts|
      row = find_or_initialize_by(day: day)
      next if row.persisted? && row.observed_at > at
      row.update!(counts: counts, observed_at: at)
    end
  end

  def self.totals(days)
    METRICS.keys.index_with { |metric| days.sum { |day| day.count(metric) } }.then { |totals| totals.merge(engagements: ENGAGEMENTS.sum { totals[_1] }) }
  end

  def count(metric)
    METRICS.fetch(metric).sum { |type| counts.fetch(type, {}).values.sum }
  end
end
