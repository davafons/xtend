require "test_helper"

class TodaySessionTest < ActionDispatch::IntegrationTest
  setup do
    @person = Person.resolve_profile!(profile)
    @post = @person.posts.create!(x_id: "8001", body: "Shipping a Rails app &gt; today", published_at: 1.hour.ago)
  end

  test "skipped tweets can be returned to the queue from Today" do
    post post_disposition_path(@post, kind: "skipped")
    follow_redirect!
    assert_includes response.body, "Set aside today"
    assert_not_includes Post.opportunities, @post
    delete post_disposition_path(@post)
    assert_redirected_to root_path
    assert_includes Post.opportunities, @post
  end

  test "reporting a reply with its link waits for confirmation without counting" do
    post post_reply_report_path(@post), params: { reply_url: "https://x.com/me/status/9001" }
    follow_redirect!
    assert_includes response.body, "1 reply waiting for confirmation"
    assert_equal "https://x.com/me/status/9001", @post.reply_report.reply_url
    assert_equal 0, DailySession.current.progress
  end

  test "tweet text is shown unescaped once" do
    get root_path
    assert_includes response.body, "Shipping a Rails app &gt; today"
    assert_not_includes response.body, "&amp;gt;"
  end

  test "checking sent replies from Today returns to Today" do
    post x_sync_runs_path, params: { dataset: "own_posts", mode: "refresh", request_key: SecureRandom.uuid, return_to: "today" }
    assert_redirected_to root_path
    post x_sync_runs_path, params: { dataset: "own_posts", mode: "refresh", request_key: SecureRandom.uuid, return_to: "https://evil.example" }
    assert_redirected_to settings_path(anchor: "collection")
  end
end
