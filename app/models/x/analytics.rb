# Parses the two GraphQL responses behind X's analytics pages on x.com, which only the signed-in owner can load:
# accountOverviewDailyQuery (Overview: per-day counts by engagement type) and contentPageQuery (Content: each
# post's private totals). X leaves out zero counts, so within a covered day a missing type is zero.
class X::Analytics
  OPERATIONS = %w[accountOverviewDailyQuery contentPageQuery].freeze

  attr_reader :operation

  def initialize(operation, document, variables)
    @operation = operation
    @user = document.dig("data", "viewer_v2", "user_results", "result") || {}
    @variables = variables
  end

  # { Date => { "Displayed" => { "true" => 2, "false" => 52 }, ... } } for every day from the requested start
  # through the newest day X returned. Later days in the range aren't counted by X yet, so they stay unsaved.
  def days
    return {} unless operation == "accountOverviewDailyQuery"
    rows = Array(@user["current_time_series"]).select { |row| row["timestamp"].is_a?(Numeric) && row["count"].is_a?(Numeric) }
    return {} if rows.empty?
    day = ->(ms) { Time.at(ms / 1000, in: "UTC").to_date }
    last = day.(rows.map { _1["timestamp"] }.max)
    from = @variables["current_from"].is_a?(Numeric) ? day.(@variables["current_from"]) : day.(rows.map { _1["timestamp"] }.min)
    counts = (from..last).index_with { {} }
    rows.each do |row|
      bucket = counts[day.(row["timestamp"])] or next
      type = bucket[row["engagement_type"].to_s] ||= {}
      verified = row["is_engaging_user_verified"].to_s
      type[verified] = type.fetch(verified, 0) + row["count"].to_i
    end
    counts
  end

  # { x_id => { published_at:, body:, metrics: { "Impressions" => 194, ... } } }
  def posts
    return {} unless operation == "contentPageQuery"
    Array(@user["tweets_results"]).filter_map do |entry|
      tweet = entry["result"] || {}
      x_id = (entry["rest_id"] || tweet["rest_id"]).to_s
      next unless x_id.match?(/\A\d+\z/)
      metrics = Array(tweet["organic_metrics_total"]).to_h { |metric| [ metric["metric_type"].to_s, metric["metric_value"].to_i ] }
        .slice(*X::PostAnalytic::METRICS)
      created = tweet.dig("details", "created_at_ms")
      [ x_id, { published_at: (Time.zone.at(created / 1000) if created.is_a?(Numeric)), body: tweet.dig("details", "full_text"), metrics: metrics } ]
    end.to_h
  end
end
