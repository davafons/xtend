require "test_helper"

class ReplyOutcomesTest < ActiveSupport::TestCase
  test "mentions coverage spans each read's oldest post up to its bound, and a finished refresh back to its start" do
    backfill = mentions_run(upper_bound: 20.days.ago, posts: [ 40.days.ago, 30.days.ago ])
    mentions_run(upper_bound: 2.days.ago, status: "completed", mode: "refresh", start_time: backfill.upper_bound, posts: [])
    mentions_run(upper_bound: 1.day.ago, status: "partial", posts: [], read: false)
    X::SyncRun.create!(dataset: "mentions", mode: "capture", owner_x_id: "999", request_key: SecureRandom.uuid, page_limit: 1, upper_bound: Time.current, status: "completed")

    coverage = X::MentionCoverage.new
    assert_equal 1, coverage.spans.size
    assert coverage.covers?(35.days.ago, 10.days.ago)
    assert_not coverage.covers?(45.days.ago, 38.days.ago)
    assert_not coverage.covers?(5.days.ago, 1.day.ago)
  end

  test "the answer rate counts a direct reply back within a week, only for finished and covered weeks" do
    alice = profile(x_id: "101", handle: "alice", name: "Alice")
    bob = profile(x_id: "102", handle: "bob", name: "Bob")
    5.times { |i| ingest(x_id: "70#{i}", target_x_id: "80#{i}", occurred_at: (20 + i).days.ago, person_profile: alice) }
    ingest(x_id: "900", target_x_id: "700", direction: "incoming", classification: "continuation", occurred_at: 18.days.ago, person_profile: alice)
    ingest(x_id: "901", target_x_id: "701", direction: "incoming", classification: "continuation", occurred_at: 10.days.ago, person_profile: alice) # too late
    ingest(x_id: "902", target_x_id: "702", direction: "incoming", classification: "continuation", occurred_at: 21.days.ago, person_profile: bob) # someone else
    ingest(x_id: "710", target_x_id: "810", occurred_at: 2.days.ago, person_profile: alice) # week still open
    ingest(x_id: "720", target_x_id: "820", occurred_at: 60.days.ago, person_profile: alice) # before coverage
    ingest(x_id: "903", target_x_id: "720", direction: "incoming", classification: "continuation", occurred_at: 59.days.ago, person_profile: alice)

    covered = Struct.new(:from) { def covers?(start, finish) = start >= from && finish <= Time.current; def covered_until = Time.current }
    rate = Network::AnswerRate.new(ReplyEvent.all, coverage: covered.new(30.days.ago))

    assert_equal 7, rate.total
    assert_equal 1, rate.open
    assert_equal 5, rate.eligible.size
    assert_equal 1, rate.answered
    assert_in_delta 0.2, rate.rate
    assert_equal 1, rate.uncovered.size
    assert_equal 1, rate.answered_outside_coverage
    assert_nil Network::AnswerRate.new(ReplyEvent.where(x_id: %w[700 701]), coverage: covered.new(30.days.ago)).rate
  end

  test "follow-backs judge only people whose first reply sits between complete follower checks" do
    alice = Person.resolve_profile!(profile(x_id: "101", handle: "alice", name: "Alice"))
    bob = Person.resolve_profile!(profile(x_id: "102", handle: "bob", name: "Bob"))
    carol = Person.resolve_profile!(profile(x_id: "103", handle: "carol", name: "Carol"))
    dave = Person.resolve_profile!(profile(x_id: "104", handle: "dave", name: "Dave"))
    snapshot("followers", [ carol ], observed_at: 10.days.ago)
    snapshot("followers", [ alice ], complete: false, observed_at: 4.days.ago)
    snapshot("followers", [ alice, carol ], observed_at: 1.day.ago)
    ingest(x_id: "701", target_x_id: "801", occurred_at: 5.days.ago, person_profile: profile(x_id: "101", handle: "alice", name: "Alice"))
    ingest(x_id: "702", target_x_id: "802", occurred_at: 5.days.ago, person_profile: profile(x_id: "102", handle: "bob", name: "Bob"))
    ingest(x_id: "703", target_x_id: "803", occurred_at: 5.days.ago, person_profile: profile(x_id: "103", handle: "carol", name: "Carol"))
    ingest(x_id: "704", target_x_id: "804", occurred_at: 20.days.ago, person_profile: profile(x_id: "104", handle: "dave", name: "Dave"))

    follow_backs = Follow::FollowBacks.new(ReplyEvent.all)
    assert_equal [ alice.id, bob.id ].sort, follow_backs.judged.sort
    assert_equal [ alice.id ], follow_backs.followed
    assert_not_includes follow_backs.judged, dave.id
  end

  private

  def mentions_run(upper_bound:, posts:, status: "completed", mode: "backfill", start_time: nil, read: true)
    run = X::SyncRun.create!(dataset: "mentions", mode: mode, owner_x_id: "999", request_key: SecureRandom.uuid, page_limit: 10,
      upper_bound: upper_bound, status: status, parameters: start_time ? { "start_time" => start_time.utc.iso8601 } : {})
    if read
      X::BillingCycle.current.x_reads.create!(dataset: "mentions", resource_limit: 10, reserved_micros: 1, pricing_basis: "standard", x_sync_run: run,
        status: "committed", payload: { "data" => posts.each_with_index.map { |at, i| { "id" => "#{run.id}#{i}", "created_at" => at.utc.iso8601 } } })
    end
    run
  end
end
