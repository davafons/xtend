require "test_helper"

class ListTest < ActiveSupport::TestCase
  setup do
    @ada = Person.create!(x_id: "7", handle: "ada", name: "Ada")
    @run = X::SyncRun.create!(dataset: "posts", mode: "capture", owner_x_id: "999", request_key: SecureRandom.uuid, page_limit: 1, upper_bound: Time.current)
  end

  test "every workspace gets the three tiers once, in ladder order" do
    2.times { List.ensure_tiers! }
    assert_equal [ "Inner circle", "Circle", "Getting to know" ], List.tiers.map(&:name)
    assert_equal [ 3, 7, 14 ], List.tiers.map(&:cadence_days)
  end

  test "a person sits on one tier at a time, and on any custom lists" do
    tokyo = List.create!(name: "Tokyo devs")
    List.tier("getting_to_know").add!(@ada)
    List.tier("circle").add!(@ada)
    tokyo.add!(@ada)
    assert_equal "Circle", @ada.reload.tier_list.name
    assert_equal [ "Tokyo devs" ], @ada.custom_lists.map(&:name)
    assert_nil tokyo.add!(@ada), "adding twice changes nothing"
    assert_equal [ @ada ], List.circle_people.to_a
  end

  test "an AI can place someone on a tier only when they're on none" do
    List.tier("circle").add!(@ada)
    assert_nil List.tier("inner").add!(@ada, source: "ai")
    assert_equal "Circle", @ada.reload.tier_list.name
    cy = Person.create!(x_id: "8", handle: "cy", name: "Cy")
    assert List.tier("getting_to_know").add!(cy, source: "ai")
  end

  test "lists are found by id, tier, or name, and tiers can't be renamed through lookup" do
    custom = List.create!(name: "Rails folks")
    assert_equal custom, List.lookup("rails FOLKS")
    assert_equal "inner", List.lookup("Inner circle").tier
    assert_equal custom, List.lookup(custom.id.to_s)
    assert_nil List.lookup("nope")
  end

  test "tend: due once the cadence has passed since your last reply, fresh posts first" do
    cy = Person.create!(x_id: "8", handle: "cy", name: "Cy")
    bo = Person.create!(x_id: "9", handle: "bo", name: "Bo")
    [ @ada, cy, bo ].each { List.tier("circle").add!(_1) }
    ingest(x_id: "r1", target_x_id: "p1", occurred_at: 2.days.ago, person_profile: profile(x_id: "7", handle: "ada", name: "Ada"))
    ingest(x_id: "r2", target_x_id: "p2", occurred_at: 10.days.ago, person_profile: profile(x_id: "8", handle: "cy", name: "Cy"))
    X::SourcePost.create!(x_id: "p9", author_x_id: "9", body: "Shipped lists", published_at: 3.hours.ago, x_sync_run: @run)
    tend = Network::Tend.new
    assert_equal %w[bo cy], tend.due.map { _1.person.handle }, "Bo has a fresh post, Cy is overdue, Ada isn't due"
    assert_equal "p9", tend.due.first.fresh_post.x_id
    assert_equal [ [ "ada", 5 ] ], tend.upcoming.map { [ _1.person.handle, _1.due_in ] }
  end

  test "the pipeline places people by observed replies until they're on a tier" do
    ingest(x_id: "r1", target_x_id: "p1", person_profile: profile(x_id: "7", handle: "ada", name: "Ada"))
    ingest(x_id: "r2", target_x_id: "p2", direction: "incoming", person_profile: profile(x_id: "7", handle: "ada", name: "Ada"))
    cy = Person.create!(x_id: "8", handle: "cy", name: "Cy")
    ingest(x_id: "r3", target_x_id: "p3", person_profile: profile(x_id: "8", handle: "cy", name: "Cy"))
    columns = Network::Pipeline.new.columns.index_by(&:key)
    assert_equal [ @ada ], columns["two_way"].people
    assert_equal [ cy ], columns["replied"].people
    assert_equal "Getting to know", columns["two_way"].next_list.name

    List.tier("getting_to_know").add!(@ada)
    columns = Network::Pipeline.new.columns.index_by(&:key)
    assert_empty columns["two_way"].people
    assert_equal [ @ada ], columns["getting_to_know"].people
  end

  test "suggestions: two-way people move up, quiet circle members fade" do
    ingest(x_id: "r1", target_x_id: "p1", occurred_at: 3.days.ago, person_profile: profile(x_id: "7", handle: "ada", name: "Ada"))
    ingest(x_id: "r2", target_x_id: "p2", direction: "incoming", occurred_at: 2.days.ago, person_profile: profile(x_id: "7", handle: "ada", name: "Ada"))
    suggestions = Network::ListSuggestions.new
    assert_equal [ [ "ada", "Getting to know" ] ], suggestions.promote.map { [ _1.person.handle, _1.list.name ] }

    cy = Person.create!(x_id: "8", handle: "cy", name: "Cy")
    List.tier("circle").add!(cy).update!(created_at: 30.days.ago)
    assert_equal [ "cy" ], Network::ListSuggestions.new.fading.map { _1.person.handle }
  end
end
