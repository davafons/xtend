require "test_helper"

class DraftTest < ActiveSupport::TestCase
  test "weighted length follows X counting for links, CJK, and emoji" do
    assert_equal 5, Draft.weighted_length("hello")
    assert_equal 23 + 1 + 3, Draft.weighted_length("https://example.com/a/very/long/path/that/x/shortens and")
    assert_equal 6, Draft.weighted_length("日本語")
    assert_equal 2, Draft.weighted_length("🚀")
    assert_equal 4, Draft.weighted_length("“hi”")
  end

  test "threads split on separator lines and flag parts over the limit" do
    draft = Draft.new(body: "First post\n\n---\n\n#{'a' * 281}\n---\n   ")
    assert_equal 2, draft.parts.size
    assert draft.thread?
    assert draft.over_limit?
    assert_equal "First post", draft.title
    assert_includes draft.intent_url, "text=First%20post"
  end

  test "a draft needs some content and cannot be moved past posted" do
    assert_not Draft.new.valid?
    assert Draft.new(notes: "Answer the question about SQLite backups").valid?
    assert_nil Draft.new(status: "posted").next_status
    assert_equal "ready", Draft.new(status: "drafting").next_status
  end

  test "ready drafts link to the matching sent post without reusing one tweet" do
    run = X::SyncRun.create!(dataset: "own_posts", owner_x_id: "999", request_key: SecureRandom.uuid, mode: "refresh", page_limit: 10, upper_bound: Time.current)
    X::SourcePost.create!(x_id: "5001", author_x_id: "999", body: "Shipping a tiny Rails CRM with SQLite &amp; Hotwire https://t.co/abc", published_at: 1.hour.ago, x_sync_run: run)
    ready = Draft.create!(status: "ready", body: "Shipping a tiny Rails CRM with SQLite & Hotwire https://example.com")
    copy = Draft.create!(status: "ready", body: "Shipping a tiny Rails CRM with SQLite & Hotwire again")
    idea = Draft.create!(status: "idea", body: "Shipping a tiny Rails CRM with SQLite & Hotwire")
    Draft.link_published!
    assert_equal [ "posted", "5001" ], [ ready.reload.status, ready.posted_x_id ]
    assert_equal "ready", copy.reload.status
    assert_equal "idea", idea.reload.status
  end
end
