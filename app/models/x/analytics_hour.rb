# One hour of one metric from the heatmap on X's analytics Audience page: when people saw or acted on your posts,
# not when you posted them. Hours inside a captured window that X returned nothing for are saved as zero.
class X::AnalyticsHour < ApplicationRecord
  include WorkspaceScoped
  self.table_name = "x_analytics_hours"
  METRICS = %w[Impressions Likes Replies Retweets Bookmark Share Follows ProfileVisits].freeze

  validates :metric, inclusion: { in: METRICS }

  def self.record!(metric, hours, at:)
    hours.each do |hour, value|
      row = find_or_initialize_by(metric: metric, hour: hour)
      next if row.persisted? && row.observed_at > at
      row.update!(value: value, observed_at: at)
    end
  end
end
