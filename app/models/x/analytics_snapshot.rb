# A figure X's analytics pages give for a whole range, saved per range: "audience" is who saw you (followers or
# not, and by country) from the Audience page, "account" is your followers, verified followers, and followers
# active in the last day from the Overview page, for the day it was seen.
class X::AnalyticsSnapshot < ApplicationRecord
  include WorkspaceScoped
  self.table_name = "x_analytics_snapshots"
  KINDS = %w[audience account].freeze
  # Where English is the main language, for a rough English-audience share.
  ENGLISH_COUNTRIES = %w[US GB CA AU IE NZ].freeze

  validates :kind, inclusion: { in: KINDS }

  def self.record!(kind, from_on, to_on, data, at:)
    row = find_or_initialize_by(kind: kind, from_on: from_on, to_on: to_on)
    return if row.persisted? && row.observed_at > at
    row.update!(data: data, observed_at: at)
  end

  def self.latest(kind) = where(kind: kind).order(:observed_at).last

  # Audience: impressions from people who don't follow you, as a share.
  def outside_network_share
    split = data.dig("in_network", "Displayed") || {}
    total = split.values.sum
    split.fetch("false", 0).fdiv(total) if total.positive?
  end

  # Audience: [[country, share], ...] of impressions, largest first.
  def countries(limit = 6)
    counts = data.dig("countries", "Displayed") || {}
    total = counts.values.sum
    return [] unless total.positive?
    counts.sort_by { |_, count| -count }.first(limit).map { |country, count| [ country, count.fdiv(total) ] }
  end

  def english_share
    counts = data.dig("countries", "Displayed") || {}
    total = counts.values.sum
    counts.slice(*ENGLISH_COUNTRIES).values.sum.fdiv(total) if total.positive?
  end
end
