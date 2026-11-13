require "test_helper"
require "minitest/mock"

class OutreachAssessmentTest < ActiveSupport::TestCase
  test "clear crypto promotion is excluded and concrete coding questions rank higher" do
    interests = Current.workspace.interests
    question = Outreach::Assessment.call(body: "How do you debug SQLite migrations in Rails?", description: "Builder", interests: interests)
    promotion = Outreach::Assessment.call(body: "We are building an agent economy with huge transaction volume", description: "Airdrop hunter", interests: interests)
    assert_operator question[:rank], :>, 0
    assert_includes question[:reason], "question"
    assert_operator promotion[:rank], :<, 0
    person = Person.resolve_profile!(profile)
    hidden = person.outreach_candidates.create!(x_id: "8001", body: "Crypto promotion", published_at: Time.current, rank: promotion[:rank])
    person.create_pin!
    assert_not_includes Outreach::Candidate.opportunities, hidden
  end

  test "ambiguous words and automated replies do not count as builder relevance" do
    interests = Current.workspace.interests
    off_topic = Outreach::Assessment.call(body: "The train jumped the rails and Congress is in turmoil", description: "Political commentator", interests: interests)
    assert_operator off_topic[:rank], :<, 0
    useful = Outreach::Assessment.call(body: "Rails routing question: how do you isolate this controller?", description: nil, interests: interests)
    assert_operator useful[:rank], :>, 0
    automated = Outreach::Assessment.call(body: "Claude Code can answer your question", description: "AI bot", interests: interests, handle: "grok")
    assert_operator automated[:rank], :<, 0
  end

end
