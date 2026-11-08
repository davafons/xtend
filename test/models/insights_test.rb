require "test_helper"

class InsightsTest < ActiveSupport::TestCase
  test "activity counts replies and DMs per bucket, including empty buckets" do
    now = Time.zone.parse("2026-11-08 12:00")
    alice = profile(x_id: "201", handle: "alice")
    ingest(x_id: "1", direction: "outgoing", occurred_at: now - 1.day, person_profile: alice)
    ingest(x_id: "2", direction: "incoming", occurred_at: now - 1.day, person_profile: alice)
    ingest(x_id: "3", direction: "outgoing", occurred_at: now - 3.days, person_profile: profile(x_id: "202", handle: "bob"))
    ingest(x_id: "4", direction: "outgoing", occurred_at: now - 40.days, person_profile: profile(x_id: "203", handle: "old"))
    DirectMessage.create!(x_id: "d1", conversation_x_id: "c1", partner_x_id: "204", direction: "incoming", occurred_at: now - 1.day, source: "archive")

    activity = Network::Activity.new(period: "30d", now: now)
    assert_equal :day, activity.unit
    assert_equal 31, activity.buckets.size
    assert_equal now.beginning_of_day, activity.buckets.last
    assert_equal [ 0, 1, 0, 1, 0 ], activity.replies_sent.last(5)
    assert_equal [ 0, 0, 0, 1, 0 ], activity.replies_received.last(5)
    assert_equal 1, activity.messages.sum
    assert_equal 3, activity.partner_count, "alice, bob, and the DM partner; the 40-day-old reply is outside the period"
    assert_equal 1, activity.two_way_count

    all = Network::Activity.new(period: "all", now: now)
    assert_equal :month, all.unit
    assert_equal [ now - 40.days, now ].map { |time| time.beginning_of_month }, [ all.buckets.first, all.buckets.last ]
    assert_equal 3, all.replies_sent.sum
  end

  test "a custom range picks its bucket size, ends today at the latest, and names each bucket's dates" do
    now = Time.zone.parse("2026-11-08 12:00")
    ingest(x_id: "1", occurred_at: Time.zone.parse("2026-09-15 10:00"))
    ingest(x_id: "2", occurred_at: Time.zone.parse("2026-09-30 10:00"))

    week = Network::Activity.new(range: Date.new(2026, 9, 10)..Date.new(2026, 9, 20), now: now)
    assert week.custom?
    assert_equal :day, week.unit
    assert_equal 11, week.buckets.size
    assert_equal 1, week.replies_sent.sum, "the reply on 30 September is outside the range"

    months = Network::Activity.new(range: Date.new(2026, 9, 3)..Date.new(2027, 1, 1), now: now)
    assert_equal :week, months.unit
    assert_equal now.end_of_day.to_date, months.ends_at.to_date
    assert_equal [ Date.new(2026, 9, 3), Date.new(2026, 9, 6) ], months.bucket_dates(months.buckets.first), "the first week starts at the range"
    assert_equal [ Date.new(2026, 11, 2), Date.new(2026, 11, 8) ], months.bucket_dates(months.buckets.last), "the last week ends today"

    assert_equal "90d", Network::Activity.new(range: Date.new(2027, 1, 1)..Date.new(2027, 2, 1), now: now).period, "a range entirely in the future is ignored"
  end

  test "people you talked with in a range come from replies and DMs in either direction" do
    alice = Person.resolve_profile!(profile(x_id: "201", handle: "alice"))
    bob = Person.resolve_profile!(profile(x_id: "202", handle: "bob"))
    Person.resolve_profile!(profile(x_id: "203", handle: "carol"))
    ingest(x_id: "1", direction: "incoming", occurred_at: 2.days.ago, person_profile: profile(x_id: "201", handle: "alice"))
    ingest(x_id: "2", occurred_at: 20.days.ago, person_profile: profile(x_id: "203", handle: "carol"))
    DirectMessage.create!(x_id: "d1", conversation_x_id: "c1", partner_x_id: "202", direction: "outgoing", occurred_at: 1.day.ago, source: "archive")

    assert_equal [ alice, bob ], Person.talked_between(5.days.ago..Time.current).order(:x_id).to_a
  end

  test "follower changes count gains and losses per tracked check, with the baseline unknown" do
    alice, bob, carol = %w[301 302 303].map { |id| Person.resolve_profile!(profile(x_id: id, handle: "p#{id}")) }
    [ [ alice, bob ], [ bob, carol ], [ carol ] ].each_with_index do |people, index|
      Follow::FollowerPeriod.observe!(snapshot("followers", people, observed_at: (3 - index).days.ago))
    end

    assert_equal [ [ nil, nil ], [ 1, 1 ], [ 0, 1 ] ], Follow::Snapshot.follower_changes.map { |_, gained, lost| [ gained, lost ] }
    assert_equal [ [ 0, 1 ] ], Follow::Snapshot.follower_changes(since: 30.hours.ago).map { |_, gained, lost| [ gained, lost ] }
  end

  test "activity with nothing saved is empty and an unknown period falls back to 90 days" do
    activity = Network::Activity.new(period: "bogus")
    assert_equal "90d", activity.period
    assert activity.empty?
    assert_equal 0, activity.replies_sent.sum
  end

  test "follower counts leave incomplete checks without a count" do
    people = %w[301 302 303].map { |id| Person.resolve_profile!(profile(x_id: id, handle: "p#{id}")) }
    snapshot("followers", people.first(2), observed_at: 3.days.ago)
    snapshot("followers", people.first(1), complete: false, observed_at: 2.days.ago)
    snapshot("followers", people, observed_at: 1.day.ago)
    snapshot("following", people, observed_at: 1.day.ago)

    assert_equal [ 2, nil, 3 ], Follow::Snapshot.follower_counts.map(&:last)
    assert_equal [ nil, 3 ], Follow::Snapshot.follower_counts(since: 50.hours.ago).map(&:last)
    assert_equal [ 2, nil ], Follow::Snapshot.follower_counts(since: 4.days.ago, before: 30.hours.ago).map(&:last)
  end
end
