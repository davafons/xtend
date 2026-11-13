require "test_helper"
require "minitest/mock"

class DiscoveryTest < ActiveSupport::TestCase
  test "clear crypto promotion is excluded and concrete coding questions rank higher" do
    interests = Current.workspace.interests
    question = Discovery::Assessment.call(body: "How do you debug SQLite migrations in Rails?", description: "Builder", interests: interests)
    promotion = Discovery::Assessment.call(body: "We are building an agent economy with huge transaction volume", description: "Airdrop hunter", interests: interests)
    assert_operator question[:rank], :>, 0
    assert_includes question[:reason], "question"
    assert_operator promotion[:rank], :<, 0
    person = Person.resolve_profile!(profile)
    hidden = person.posts.create!(x_id: "8001", body: "Crypto promotion", published_at: Time.current, rank: promotion[:rank])
    person.create_pin!
    assert_not_includes Post.opportunities, hidden
  end

  test "ambiguous words and automated replies do not count as builder relevance" do
    interests = Current.workspace.interests
    off_topic = Discovery::Assessment.call(body: "The train jumped the rails and Congress is in turmoil", description: "Political commentator", interests: interests)
    assert_operator off_topic[:rank], :<, 0
    useful = Discovery::Assessment.call(body: "Rails routing question: how do you isolate this controller?", description: nil, interests: interests)
    assert_operator useful[:rank], :>, 0
    automated = Discovery::Assessment.call(body: "Claude Code can answer your question", description: "AI bot", interests: interests, handle: "grok")
    assert_operator automated[:rank], :<, 0
  end

end
