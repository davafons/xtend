# Parses the GraphQL responses behind X's analytics pages on x.com, which only the signed-in owner can load:
# accountOverviewDailyQuery (Overview: per-day counts by engagement type, plus your followers right now),
# contentPageQuery (Content: each post's and reply's private totals), and audienceOverviewDataQuery (Audience: an
# hourly heatmap of one metric, and who saw you by network and country). X leaves out zero counts, so inside a
# covered day or hour a missing value is zero.
class X::Analytics
  OPERATIONS = %w[accountOverviewDailyQuery contentPageQuery audienceOverviewDataQuery].freeze
  LEGACY_METRICS = %w[VideoViews MediaViews].freeze
  URL = "https://x.com/i/account_analytics/overview"
  # Nothing collects X analytics on its own, so after this long without a visit the app asks for one.
  STALE_AFTER = 7.days

  # When the extension last saved anything from X's analytics pages, or nil.
  def self.last_collected_at
    [ X::AccountDay.maximum(:observed_at), X::PostAnalytic.maximum(:observed_at), X::AnalyticsHour.maximum(:observed_at) ].compact.max
  end

  def self.stale?(at = last_collected_at)
    at.nil? || at < STALE_AFTER.ago
  end

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
    # Video and media views come only in the older per-day list, without the verified split.
    Array(@user["legacy_current_metrics"]).each do |entry|
      bucket = counts[Date.parse(entry.dig("timestamp", "iso8601_time").to_s)] rescue next
      next unless bucket
      Array(entry["metric_values"]).each do |metric|
        bucket[metric["metric_type"]] = { "all" => metric["metric_value"].to_i } if LEGACY_METRICS.include?(metric["metric_type"]) && metric["metric_value"]
      end
    end
    counts
  end

  # Your followers as the Overview page saw them: { "followers" =>, "verified_followers" =>, "active_followers" => }.
  def account
    return unless operation == "accountOverviewDailyQuery"
    data = { "followers" => @user.dig("relationship_counts", "followers"), "verified_followers" => @user["verified_follower_count"],
      "active_followers" => @user.dig("realtime_active_followers", "active_count") }.transform_values { |value| Integer(value, exception: false) }.compact
    data.presence
  end

  # The Audience heatmap: [metric, { hour => value }] for every hour from the window's start through the newest hour
  # X returned.
  def hours
    return unless operation == "audienceOverviewDataQuery"
    metric = Array(@variables["requested_metrics"]).first.to_s
    return unless X::AnalyticsHour::METRICS.include?(metric)
    values = Array(@user["organic_metrics_time_series"]).filter_map do |row|
      at = Time.iso8601(row.dig("timestamp", "iso8601_time").to_s).beginning_of_hour rescue next
      [ at, Array(row["metric_values"]).sum { |value| value["metric_type"] == metric ? value["metric_value"].to_i : 0 } ]
    end.to_h
    start = (Time.iso8601(@variables["heatmap_from_time_incl"].to_s) rescue values.keys.min)&.beginning_of_hour
    return [ metric, {} ] if values.empty? || start.nil?
    hours = Enumerator.produce(start) { _1 + 1.hour }.take_while { _1 <= values.keys.max }
    [ metric, hours.index_with { |hour| values.fetch(hour, 0) } ]
  end

  # Who saw you over the Audience page's range: [from, to, { "in_network" => { type => { "true" =>, "false" => } },
  # "countries" => { type => { "JP" => n } } }].
  def audience
    return unless operation == "audienceOverviewDataQuery"
    from, to = @variables.values_at("from_time_incl", "to_time_excl")
    return unless from.is_a?(Numeric) && to.is_a?(Numeric)
    tally = ->(rows, key) do
      rows.each_with_object(Hash.new { |hash, type| hash[type] = Hash.new(0) }) do |row, sums|
        sums[row["engagement_type"].to_s][row[key].to_s] += row["count"].to_i
      end
    end
    [ Time.at(from / 1000, in: "UTC").to_date, Time.at(to / 1000, in: "UTC").to_date,
      { "in_network" => tally.(Array(@user["uec_metrics_daily_time_series_count"]), "is_in_network"),
        "countries" => tally.(Array(@user["uec_country_metrics_daily_time_series_count"]), "country") }.as_json ]
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
