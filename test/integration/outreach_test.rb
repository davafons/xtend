require "test_helper"

class OutreachPageTest < ActionDispatch::IntegrationTest
  test "shows session progress, posts worth a reply with their reason, and people to engage with filters" do
    run = X::SyncRun.create!(dataset: "posts", mode: "capture", owner_x_id: "999", request_key: SecureRandom.uuid, page_limit: 1, upper_bound: Time.current)
    alice = Person.resolve_profile!(profile(x_id: "101", handle: "alice", name: "Alice"))
    X::Interaction.record!(kind: "reply", source: "101", target: "999", post: "11", occurred_at: 1.day.ago)
    X::SourcePost.create!(x_id: "5001", author_x_id: "101", body: "Anyone tried SQLite for queues?", language: "en", published_at: 1.hour.ago, x_sync_run: run)
    ingest(x_id: "7001", target_x_id: "8001", person_profile: profile(x_id: "102", handle: "bob", name: "Bob"))

    get outreach_path
    assert_response :success
    assert_select "nav[aria-label=Outreach] a[aria-current=page]", text: /Reply now/
    assert_select "#outreach-session", text: /of 20 new targets\s*1\b/
    assert_select "#opening_5001", text: /1 from them | none seen from you/
    assert_select "#opening_5001 a[href='https://x.com/alice/status/5001'][aria-label='Reply on X']"
    assert_select "h1", count: 1, text: "Outreach"
    assert_select "h1.sr-only"

    get outreach_path(view: "people", reason: "reach_back")
    assert_response :success
    assert_select "#prospect_101", text: /Alice/
    assert_select "#prospect_101 a[href='https://x.com/alice/status/5001']"
    assert_select "nav[aria-label=Why] a[aria-current=true]", text: /Reaching out/

    get outreach_path(view: "people", reason: "network")
    assert_select "#prospect_101", count: 0
    assert_includes response.body, "Nobody for this reason right now."
    assert alice.reload.pin.nil?
  end

  test "Reply now shows today's share split into circle and reach, the whole list on request, and a done state" do
    run = X::SyncRun.create!(dataset: "posts", mode: "capture", owner_x_id: "999", request_key: SecureRandom.uuid, page_limit: 1, upper_bound: Time.current)
    alice = Person.resolve_profile!(profile(x_id: "101", handle: "alice", name: "Alice"))
    Person.resolve_profile!(profile(x_id: "102", handle: "bob", name: "Bob"))
    List.ensure_tiers!
    List.find_by!(tier: "inner").people << alice
    Person.all.each { |person| X::Interaction.record!(kind: "reply", source: person.x_id, target: "999", post: "1#{person.x_id}", occurred_at: 1.day.ago) }
    X::SourcePost.create!(x_id: "5001", author_x_id: "101", body: "Circle post", language: "en", published_at: 1.hour.ago, x_sync_run: run)
    X::SourcePost.create!(x_id: "5002", author_x_id: "102", body: "Reach post", language: "en", published_at: 1.hour.ago, x_sync_run: run)

    get outreach_path
    assert_select "section[aria-label=Circle] #opening_5001"
    assert_select "section[aria-label=Reach] #opening_5002"
    assert_includes response.body, "2 posts for the 20 replies left today"
    assert_select "a[href='#{outreach_path(all: 1)}']", text: "See the whole list"

    get outreach_path(all: 1)
    assert_select "section[aria-label=Circle]", count: 0
    assert_select "#opening_5001"
    assert_select "#opening_5002"

    20.times { |n| ingest(x_id: "70#{n}", target_x_id: "80#{n}", occurred_at: 1.minute.ago, person_profile: profile(x_id: "6#{n}", handle: "done#{n}")) }
    assert_equal 0, Outreach::Session.current.remaining
    get outreach_path
    assert_includes response.body, "Done for today."
    assert_select "#opening_5001", count: 0
    assert_select "a[href='#{outreach_path(all: 1)}']", text: "Keep going"
  end

  test "an empty workspace shows honest empty states" do
    get outreach_path
    assert_response :success
    assert_includes response.body, "No fresh posts to answer."
    get outreach_path(view: "people")
    assert_includes response.body, "No one to suggest yet."
  end
end
