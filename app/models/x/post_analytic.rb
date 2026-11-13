# A post's private totals from X's analytics Content tab on x.com: impressions and what people did after seeing
# it, including profile visits and follows that the public counts don't show. Totals as of when the page loaded.
class X::PostAnalytic < ApplicationRecord
  include WorkspaceScoped
  self.table_name = "x_post_analytics"
  METRICS = %w[Impressions Engagements Likes Replies Retweets Bookmark Share Follows ProfileVisits DetailExpands UrlClicks HashtagClicks PermalinkClicks].freeze

  def self.record!(posts, at:)
    posts.each do |x_id, post|
      row = find_or_initialize_by(post_x_id: x_id)
      next if row.persisted? && row.observed_at > at
      row.update!(post.merge(observed_at: at))
    end
  end

  def metric(name) = metrics[name]
end
