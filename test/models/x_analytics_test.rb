require "test_helper"
require_relative "../test_helpers/web_capture_helper"

class XAnalyticsTest < ActiveSupport::TestCase
  include WebCaptureHelper

  def ms(date) = Time.utc(date.year, date.month, date.day).to_i * 1000

  def overview(rows, from:)
    web_response("accountOverviewDailyQuery", { data: { viewer_v2: { user_results: { result: { current_time_series: rows } } } } },
      variables: { current_from: ms(from) })
  end

  def row(type, count, date, verified: "false") = { engagement_type: type, count: count, timestamp: ms(date), is_engaging_user_verified: verified }

  test "the Overview page saves each covered day, totals as X does, and leaves days X hasn't counted unsaved" do
    first = Date.new(2026, 3, 1)
    result = capture!(overview([
      row("Displayed", 50, first), row("Displayed", 2, first, verified: "true"), row("Fav", 3, first), row("ProfilePic", 1, first),
      row("Retweet", 1, first + 2), row("QuoteTweet", 1, first + 2), row("Follow", 2, first + 2), row("Unfollow", 1, first + 2)
    ], from: first))

    assert_equal 3, result[:analytics_days]
    assert_equal 0, result[:ignored]
    days = X::AccountDay.order(:day).to_a
    assert_equal [ first, first + 1, first + 2 ], days.map(&:day)
    assert_equal({}, days[1].counts, "a covered day with nothing returned is zero")
    totals = X::AccountDay.totals(days)
    assert_equal [ 52, 3, 1, 2, 2, 1 ], totals.values_at(:impressions, :likes, :profile_visits, :reposts, :follows, :unfollows)
    assert_equal 6, totals[:engagements]
  end

  test "an older sighting of a day never replaces a newer one" do
    day = Date.new(2026, 3, 1)
    capture!(overview([ row("Displayed", 80, day) ], from: day).merge("at" => 1.minute.ago.to_i * 1000))
    capture!(overview([ row("Displayed", 40, day) ], from: day).merge("at" => 1.hour.ago.to_i * 1000))
    assert_equal 80, X::AccountDay.sole.count(:impressions)
  end

  test "the Content page saves each post's private totals, a missing value counting as zero" do
    document = { data: { viewer_v2: { user_results: { result: { tweets_results: [
      { rest_id: "2120710514557026437", result: { details: { created_at_ms: 1_794_451_762_000, full_text: "Perfect weather" },
        organic_metrics_total: [ { metric_type: "Impressions", metric_value: 194 }, { metric_type: "Follows" }, { metric_type: "ProfileVisits", metric_value: 3 } ] } }
    ] } } } } }
    result = capture!(web_response("contentPageQuery", document))
    assert_equal 1, result[:post_analytics]
    post = X::PostAnalytic.sole
    assert_equal({ "Impressions" => 194, "Follows" => 0, "ProfileVisits" => 3 }, post.metrics)
    assert_equal "Perfect weather", post.body
  end
end
