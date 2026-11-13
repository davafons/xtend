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

  test "an idea keeps its variations as alternatives and records who wrote the main text" do
    draft = Draft.capture!(texts: [ "Main take", " ", "Shorter take", "Question hook?" ], editor: "ai", note: "different hooks")
    assert_equal "ai", draft.source
    assert_equal [ "Shorter take", "Question hook?" ], draft.alternatives.map(&:body)
    assert draft.alternatives.all? { |alternative| alternative.source == "ai" && alternative.note == "different hooks" }
    assert_equal [ [ "Main take", "ai" ] ], draft.revisions.map { |revision| [ revision.body, revision.source ] }
  end

  test "quick saves by one author share a revision, and a new author or a later save starts another" do
    draft = Draft.capture!(texts: [ "From Grok" ], editor: "ai")
    draft.update!(body: "Edited once")
    draft.update!(body: "Edited twice")
    assert_equal [ "Edited twice", "From Grok" ], draft.revisions.newest_first.map(&:body)
    assert_equal "owner", draft.reload.source
    travel 11.minutes do
      draft.update!(body: "Edited later")
      assert_equal 3, draft.revisions.count
    end
  end

  test "using an alternative swaps it with the main text, and restoring adds a step instead of rewriting history" do
    draft = Draft.capture!(texts: [ "Original", "Alternative from Grok" ], editor: "ai")
    draft.update!(body: "Original, edited by me")
    draft.use_alternative!(draft.alternatives.first)
    assert_equal "Alternative from Grok", draft.body
    assert_equal "ai", draft.source
    assert_equal [ [ "Original, edited by me", "owner", "Previous main version" ] ], draft.alternatives.reload.map { |a| [ a.body, a.source, a.note ] }
    assert_equal [ "Alternative from Grok", "Original, edited by me", "Original" ], draft.revisions.newest_first.map(&:body)
    draft.restore!(draft.revisions.find_by(body: "Original, edited by me"))
    assert_equal "Original, edited by me", draft.body
    assert_equal 4, draft.revisions.count
  end

  test "a draft keeps a bounded number of alternatives" do
    draft = Draft.capture!(texts: [ "Main" ])
    draft.add_alternatives!(Array.new(Draft::MAX_ALTERNATIVES) { |index| "Version #{index}" })
    assert_raises(ActiveRecord::RecordInvalid) { draft.add_alternatives!([ "One more" ]) }
  end
end
