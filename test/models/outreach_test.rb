require "test_helper"

class OutreachTest < ActiveSupport::TestCase
  setup do
    @run = X::SyncRun.create!(dataset: "posts", mode: "capture", owner_x_id: "999", request_key: SecureRandom.uuid, page_limit: 1, upper_bound: Time.current)
  end

  def person(x_id, handle)
    Person.resolve_profile!(profile(x_id: x_id, handle: handle, name: handle.capitalize))
  end

  def interaction(source, target, post, at: 1.day.ago, kind: "reply")
    X::Interaction.record!(kind: kind, source: source, target: target, post: post, occurred_at: at)
  end

  def post(x_id, author, at: 2.hours.ago, language: "en", reply_to: nil)
    X::SourcePost.create!(x_id: x_id, author_x_id: author, body: "Post #{x_id}", language: language, published_at: at,
      reply_to_x_id: reply_to, x_sync_run: @run)
  end

  def reasons(prospects, x_id)
    prospects.find(x_id)&.reasons&.map(&:key)
  end

  test "ranks people who reach out more, quiet two-way people, posting mutuals, and network neighbors, each with a reason" do
    alice = person("101", "alice")
    bob = person("102", "bob")
    carol = person("103", "carol")
    dave = person("104", "dave")
    snapshot("following", [ carol ])
    snapshot("followers", [ carol ])

    interaction("101", "999", "a1")
    interaction("101", "999", "a2", kind: "mention")
    ingest(x_id: "b1", target_x_id: "b0", direction: "outgoing", occurred_at: 30.days.ago, person_profile: profile(x_id: "102", handle: "bob", name: "Bob"))
    ingest(x_id: "b2", target_x_id: "b1", direction: "incoming", classification: "continuation", occurred_at: 29.days.ago, person_profile: profile(x_id: "102", handle: "bob", name: "Bob"))
    post("3001", "103")
    interaction("101", "104", "d1")
    interaction("102", "104", "d2", kind: "quote")

    prospects = Outreach::Prospects.new
    assert_equal [ "reach_back" ], reasons(prospects, "101")
    assert_equal "2 from them · none seen from you", prospects.find("101").reasons.first.detail
    assert_equal [ "quiet" ], reasons(prospects, "102")
    assert_match(/Two-way · quiet 29d/, prospects.find("102").reasons.first.detail)
    assert_equal [ "posting" ], reasons(prospects, "103")
    assert_equal "Mutual · 1 new post", prospects.find("103").reasons.first.detail
    assert_equal [ "network" ], reasons(prospects, "104")
    assert_equal "2 of your people talk to them", prospects.find("104").reasons.first.detail
    assert_equal "101", prospects.to_a.first.x_id, "reaching out ranks above other reasons"
    assert_equal [ "104" ], Outreach::Prospects.new(reason: "network").to_a.map(&:x_id)
    assert_equal({ "reach_back" => 1, "quiet" => 1, "posting" => 1, "network" => 1 }, prospects.counts)
    assert_equal [ alice, bob, carol, dave ].map(&:id).sort, prospects.all.filter_map(&:person).map(&:id).sort
  end

  test "missing or recent contact never becomes a reason, and automated accounts are left out" do
    person("101", "alice")
    person("105", "grok")
    person("106", "frank")
    interaction("101", "999", "a1")
    interaction("101", "999", "a2")
    interaction("999", "101", "y1", at: 1.hour.ago)
    interaction("105", "999", "g1")
    interaction("106", "999", "f1", kind: "like")
    interaction("999", "106", "f2", kind: "like", at: 2.days.ago)

    prospects = Outreach::Prospects.new
    assert_nil prospects.find("101"), "you reached them within the cooldown"
    assert_nil prospects.find("105")
    assert_nil prospects.find("106"), "even counts are not reaching out more, and recent contact is not quiet"
  end

  test "a person's new posts skip answered, set-aside, non-English and reply posts, and pins survive" do
    carol = person("103", "carol")
    Pin.create!(person: carol)
    post("3001", "103", at: 1.hour.ago)
    post("3002", "103", at: 3.hours.ago)
    post("3003", "103", language: "ja")
    post("3004", "103", reply_to: "555")
    post("3005", "103", at: 3.days.ago)
    ingest(x_id: "r1", target_x_id: "3002", person_profile: profile(x_id: "103", handle: "carol", name: "Carol"))

    prospects = Outreach::Prospects.new
    assert_equal [ "3001" ], prospects.find("103").recent_posts.map(&:x_id)
    assert_equal "Pinned · 1 new post", prospects.find("103").reasons.first.detail
    assert carol.reload.pin, "ranking never touches manual preferences"
  end

  test "openings cap posts per author, add discovery picks with their reason, and rank fresher posts first" do
    person("103", "carol")
    snapshot("following", Person.all)
    snapshot("followers", Person.all)
    post("3001", "103", at: 1.hour.ago)
    post("3002", "103", at: 2.hours.ago)
    post("3003", "103", at: 3.hours.ago)
    stranger = person("107", "erin")
    Post.create!(person: stranger, x_id: "4001", body: "How do you test Rails migrations?", published_at: 1.hour.ago, rank: 45, match_reason: "Matches Rails and databases.")

    openings = Outreach::Openings.new(Outreach::Prospects.new).to_a
    assert_equal %w[4001 3001 3002], openings.map(&:x_id)
    assert_equal "Matches Rails and databases.", openings.first.discovery.match_reason
    assert_equal "https://x.com/carol/status/3001", openings.second.url
  end

  test "the session counts distinct new targets and reports follow-ups separately" do
    session = DailySession.current
    ingest(x_id: "o1", target_x_id: "t1", occurred_at: 1.minute.ago)
    ingest(x_id: "o2", target_x_id: "o0", classification: "continuation", occurred_at: 1.minute.ago)
    assert_equal 1, session.reload.progress
    assert_equal 19, session.remaining
    assert_equal 1, session.follow_ups
    assert_equal [ "builder" ], session.targets.map { |outreach| outreach.reply_event.person.handle }
  end
end
