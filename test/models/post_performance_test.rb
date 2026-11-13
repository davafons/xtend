require "test_helper"

class PostPerformanceTest < ActiveSupport::TestCase
  setup { @run = X::SyncRun.create!(dataset: "posts", mode: "capture", owner_x_id: "999", request_key: SecureRandom.uuid, page_limit: 1, upper_bound: Time.current) }

  test "compares settled top-level posts by format with medians, and counts who replied" do
    own("1", media_kinds: "photo", views: 100, likes: 1)
    own("2", media_kinds: "photo", views: 300, likes: 5)
    own("3", media_kinds: "photo", views: 10_000, likes: 90)
    own("4", media_kinds: "animated_gif", views: 50)
    own("5", has_link: true, views: 70)
    own("6", views: 40)
    own("7", views: 999, observed: 1.hour.ago, published: 2.hours.ago) # too fresh
    X::SourcePost.create!(x_id: "8", author_x_id: "999", body: "reply", parent_x_id: "1", published_at: 3.days.ago, x_sync_run: @run, view_count: 5000, metrics_observed_at: Time.current)
    X::SourcePost.create!(x_id: "9", author_x_id: "999", body: "no counts", published_at: 3.days.ago, x_sync_run: @run)
    2.times { |i| ingest(x_id: "90#{i}", target_x_id: "3", direction: "incoming", classification: "continuation", person_profile: profile(x_id: "10#{i}", handle: "p#{i}", name: "P#{i}")) }

    performance = Network::PostPerformance.new
    rows = performance.by_format.index_by(&:format)
    assert_equal [ 3, 300, 5, 2 ], rows["photo"].to_h.values_at(:posts, :views, :likes, :people)
    assert_equal %w[photo link video text], performance.by_format.map(&:format)
    assert_equal %w[3 2 1 5 4], performance.top.map(&:x_id)
    assert_equal 1, performance.fresh_count
    assert_equal 1, performance.uncounted_count
  end

  private

  def own(x_id, views:, likes: nil, media_kinds: nil, has_link: false, published: 5.days.ago, observed: 1.day.ago)
    X::SourcePost.create!(x_id: x_id, author_x_id: "999", body: "Post #{x_id}", published_at: published, x_sync_run: @run,
      view_count: views, like_count: likes, media_kinds: media_kinds, has_link: has_link, metrics_observed_at: observed)
  end
end
