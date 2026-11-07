# A post's public counts at one sighting. One row per post, surface, and hour, so scrolling past the same post
# again doesn't pile up rows but its growth over a day is still visible.
class X::PostObservation < ApplicationRecord
  include WorkspaceScoped
  self.table_name = "x_post_observations"
  SURFACES = %w[home search profile thread list likes bookmarks other].freeze
  METRICS = %i[reply_count like_count repost_count quote_count bookmark_count view_count].freeze

  validates :surface, inclusion: { in: SURFACES }

  def self.record!(post_x_id, surface:, metrics:, at: Time.current)
    hour = at.beginning_of_hour
    observation = where(post_x_id: post_x_id, surface: surface, observed_at: hour..hour.end_of_hour).first ||
      new(post_x_id: post_x_id, surface: surface)
    observation.assign_attributes(metrics.slice(*METRICS).merge(observed_at: at))
    observation.save!
  end
end
