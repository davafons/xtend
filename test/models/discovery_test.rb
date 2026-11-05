require "test_helper"
require "minitest/mock"

class DiscoveryTest < ActiveSupport::TestCase
  test "source links stage without fabricated identities or network calls" do
    assert_difference "DiscoverySuggestion.count", 1 do
      assert_equal 1, DiscoverySuggestion.capture_links!("Useful: https://x.com/builder/status/123?source=grok\nhttps://twitter.com/builder/status/123")
    end
    assert_equal "https://x.com/builder/status/123", DiscoverySuggestion.first.source_url
    assert_equal 0, Person.count
    assert_equal 0, Post.count
    assert_equal 0, XRead.count
    assert_no_difference "DiscoverySuggestion.count" do
      assert_raises(DiscoverySuggestion::Invalid) { DiscoverySuggestion.capture_links!("https://x.com/builder/status/456\nhttps://x.com.evil.example/builder/status/789") }
    end
    assert_equal ["123"], DiscoverySuggestion.pluck(:post_x_id)
  end

  test "clear crypto promotion is excluded and concrete coding questions rank higher" do
    interests = Workspace.current.interests
    question = DiscoveryAssessment.call(body: "How do you debug SQLite migrations in Rails?", description: "Builder", interests: interests)
    promotion = DiscoveryAssessment.call(body: "We are building an agent economy with huge transaction volume", description: "Airdrop hunter", interests: interests)
    assert_operator question[:rank], :>, 0
    assert_includes question[:reason], "question"
    assert_operator promotion[:rank], :<, 0
    person = Person.resolve_profile!(profile)
    hidden = person.posts.create!(x_id: "8001", body: "Crypto promotion", published_at: Time.current, rank: promotion[:rank])
    person.create_pin!
    assert_not_includes Post.opportunities, hidden
  end

  test "resolving a saved link creates a candidate only once its numeric author is known" do
    run = XSyncRun.create!(owner_x_id: "999", dataset: "posts", mode: "discovery", page_limit: 1,
      upper_bound: Time.current, request_key: SecureRandom.uuid, parameters: {"purpose" => "discovery"})
    DiscoverySuggestion.capture_links!("https://x.com/builder/status/8001")
    XSourcePost.capture!({"id" => "8001", "author_id" => "101", "text" => "How do you test Rails jobs?", "created_at" => Time.current.iso8601, "lang" => "en", "referenced_posts" => []}, run: run)
    XSourcePost.reconcile_all!
    assert_equal 0, Post.count
    Person.resolve_profile!(profile)
    XSourcePost.reconcile_all!
    assert_equal 1, Post.opportunities.count
    assert_equal "You saved this source for review. Contains a question or an implementation problem.", Post.first.match_reason
    assert_equal 0, ReplyEvent.count
    assert_equal 0, XRead.count
  end
  test "ambiguous words and automated replies do not count as builder relevance" do
    interests = Workspace.current.interests
    off_topic = DiscoveryAssessment.call(body: "The train jumped the rails and Congress is in turmoil", description: "Political commentator", interests: interests)
    assert_operator off_topic[:rank], :<, 0
    useful = DiscoveryAssessment.call(body: "Rails routing question: how do you isolate this controller?", description: nil, interests: interests)
    assert_operator useful[:rank], :>, 0
    automated = DiscoveryAssessment.call(body: "Claude Code can answer your question", description: "AI bot", interests: interests, handle: "grok")
    assert_operator automated[:rank], :<, 0
  end

end
