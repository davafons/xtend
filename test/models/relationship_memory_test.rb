require "test_helper"

class RelationshipMemoryTest < ActiveSupport::TestCase
  test "verified replies automatically create a person and progress once" do
    event = ingest
    assert_equal "A Builder", event.person.name
    assert_equal "You replied only", event.person.reply_state
    assert_equal 1, DailySession.current.progress
    assert_no_difference ["Person.count", "ReplyEvent.count", "Outreach.count"] do
      ingest
    end
  end

  test "repeat replies to the same target and followups do not inflate progress" do
    ingest
    ingest(x_id: "7002")
    ingest(x_id: "7003", target_x_id: "8002", classification: "continuation")
    ingest(x_id: "7004", target_x_id: "8003", classification: "unclassified")
    assert_equal 1, DailySession.current.progress
    assert_equal 4, Person.first.outgoing_count
  end

  test "independent targets by the same person both count" do
    ingest
    ingest(x_id: "7002", target_x_id: "8002")
    assert_equal 2, DailySession.current.progress
    assert_equal 1, Person.count
  end

  test "all-history reply states retain old exchanges and direction" do
    event = ingest(direction: "incoming", occurred_at: 3.years.ago)
    assert_equal "They replied only", event.person.reply_state
    ingest(x_id: "7002", occurred_at: 2.years.ago)
    assert_equal "Two-way", event.person.reply_state
    assert_equal 0, DailySession.current.progress
  end

  test "manual notes and pins survive profile refresh and handle change" do
    person = Person.create!(handle: "builder", name: "Manual name", notes: "Keep this personal note")
    person.create_pin!
    person.create_follow_protection!
    ingest
    assert_equal person.id, Person.find_by!(x_id: "101").id
    ingest(x_id: "7002", person_profile: profile(handle: "newhandle"))
    person.reload
    assert_equal "newhandle", person.handle
    assert_equal "Keep this personal note", person.notes
    assert person.pin
    assert person.follow_protection
  end

  test "self replies cannot create outreach" do
    assert_no_difference "Outreach.count" do
      assert_raises ActiveRecord::RecordInvalid do
        ingest(person_profile: profile(x_id: "999", handle: "myself"))
      end
    end
  end

  test "unknown account identity prevents verified history" do
    Current.workspace.update!(owner_x_id: nil)
    assert_raises(ActiveRecord::RecordInvalid) { ingest }
    assert_equal 0, ReplyEvent.count
  end

  test "unfinished session survives midnight and completion waits for target" do
    travel_to Time.zone.parse("2026-11-04 23:50") do
      event = ingest
      session = DailySession.current
      assert_raises(ActiveRecord::RecordInvalid) { session.complete! }
      travel 2.hours
      ingest(x_id: "7002", target_x_id: "8002")
      assert_equal session.id, DailySession.current.id
      assert_equal 2, DailySession.current.progress
    end
  end

  test "cleanup excludes mutuals keeps and recent replies but suggests long-quiet accounts" do
    mutual = Person.resolve_profile!(profile(x_id: "1", handle: "mutual"))
    kept = Person.resolve_profile!(profile(x_id: "2", handle: "kept"))
    kept.create_follow_protection!
    old = ingest(occurred_at: 4.years.ago).person
    recent = ingest(x_id: "7002", target_x_id: "8002", direction: "incoming", occurred_at: 10.days.ago, person_profile: profile(x_id: "4", handle: "recent")).person
    candidate = Person.resolve_profile!(profile(x_id: "3", handle: "candidate"))
    snapshot("following", [mutual, kept, old, recent, candidate])
    snapshot("followers", [mutual])
    assert_equal [old.id, candidate.id].sort, cleanup_ids.sort
    assert_equal [candidate.id], cleanup_ids("strangers")
    assert_equal "reply", Person::Interactions.for(old).latest.channel
    assert_nil Person::Interactions.for(candidate).latest
    assert_equal "Mutual", mutual.follow_state
  end

  test "partial and stale follower data cannot drive cleanup" do
    person = Person.resolve_profile!(profile)
    snapshot("following", [person])
    snapshot("followers", [], observed_at: 2.days.ago)
    assert_empty cleanup_ids
    snapshot("followers", [])
    assert_equal [person.id], cleanup_ids
    snapshot("followers", [], complete: false, observed_at: 1.second.from_now)
    assert_empty cleanup_ids
  end

  test "manual unfollow reporting does not rewrite graph facts" do
    person = Person.resolve_profile!(profile)
    snapshot("following", [person])
    snapshot("followers", [])
    Follow::Review.record!(person, "reported_unfollow")
    assert_equal "You follow", person.follow_state
    assert_empty cleanup_ids
  end

  test "English queue honors prior targets" do
    person = Person.resolve_profile!(profile)
    post = person.posts.create!(x_id: "8001", body: "Hello", published_at: 1.hour.ago)
    person.posts.create!(x_id: "8002", body: "Hola", language: "es", published_at: 1.hour.ago)
    assert_equal [post.id], Post.opportunities.pluck(:id)
    ingest
    assert_empty Post.opportunities
  end

  test "Grok export excludes private notes and does not imply complete data" do
    person = Person.resolve_profile!(profile)
    person.update!(notes: "Private material")
    context = Current.workspace.grok_context
    assert_equal "twitter-crm-context-v1", context[:format]
    assert_not_includes context.to_json, "Private material"
    assert_includes context[:coverage], "not a complete"
  end
  test "completed sessions stay complete until a new day" do
    20.times { |index| ingest(x_id: (7000 + index).to_s, target_x_id: (8000 + index).to_s) }
    session = DailySession.current
    session.complete!
    assert_equal session.id, DailySession.current.id
    travel 1.day do
      assert_not_equal session.id, DailySession.current.id
      assert_equal 0, DailySession.current.progress
    end
  end

  test "source identity cannot absorb an unrelated unresolved person" do
    person = Person.create!(name: "Someone", handle: "someone")
    assert_raises(ArgumentError) { Person.resolve_profile!(x_id: nil, handle: "other", name: "Other") }
    assert_equal "someone", person.reload.handle
  end

  test "a confirmed source ID cannot change target on reimport" do
    ingest
    assert_raises(ArgumentError) { ingest(target_x_id: "9999") }
    assert_equal "8001", ReplyEvent.first.target_x_id
    assert_equal 1, DailySession.current.progress
  end

  test "a verified continuation doesn't count as outreach" do
    person = Person.resolve_profile!(profile)
    post = person.posts.create!(x_id: "8001", body: "An existing conversation", published_at: 1.hour.ago)
    ingest(classification: "continuation")
    assert_equal 0, DailySession.current.progress
    assert_not_includes Post.opportunities, post
  end

  test "later proof of a continuation corrects outreach while preserving the reply" do
    event = ingest
    assert_equal 1, DailySession.current.progress
    ingest(classification: "continuation")
    assert_equal "continuation", event.reload.classification
    assert_equal 0, DailySession.current.progress
    assert_equal 1, ReplyEvent.count
    assert_equal "You replied only", event.person.reply_state
  end

end
