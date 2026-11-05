require "test_helper"

class FollowerPeriodTest < ActiveSupport::TestCase
  def observed(people, at:, complete: true)
    record = snapshot("followers", people, observed_at: at, complete: complete)
    Follow::FollowerPeriod.observe!(record)
    record
  end

  test "baseline unknown starts stay separate from observed losses and refollows" do
    freeze_time
    person = Person.resolve_profile!(profile)
    first = observed([person], at: 20.days.ago)
    period = Follow::FollowerPeriod.first
    assert period.baseline?
    assert_nil Follow::FollowerPeriod.completed_duration_summary
    assert_no_difference "Follow::FollowerPeriod.count" do
      Follow::FollowerPeriod.observe!(first)
      observed([], at: 19.days.ago, complete: false)
    end
    assert_nil period.reload.ended_by
    observed([person], at: 15.days.ago)
    lost = observed([], at: 10.days.ago)
    assert_equal lost.observed_at, period.reload.ended_by
    assert_equal 15.days.ago.to_i, period.last_seen_at.to_i
    assert_nil Follow::FollowerPeriod.completed_duration_summary
    followed_again = observed([person], at: 5.days.ago)
    assert_equal 2, person.follower_periods.count
    fresh = Follow::FollowerPeriod.ongoing.first
    assert_equal lost.observed_at, fresh.followed_after
    assert_equal followed_again.observed_at, fresh.first_seen_at
  end

  test "completed periods report duration bounds and exclude ongoing followers" do
    person = Person.resolve_profile!(profile)
    other = Person.resolve_profile!(profile(x_id: "102", handle: "other"))
    observed([], at: 20.days.ago)
    observed([person, other], at: 15.days.ago)
    observed([person, other], at: 10.days.ago)
    observed([other], at: 5.days.ago)
    summary = Follow::FollowerPeriod.completed_duration_summary
    assert_equal 1, summary[:count]
    assert_in_delta 5, summary[:minimum_days], 0.001
    assert_in_delta 15, summary[:maximum_days], 0.001
    assert_equal 1, summary[:ongoing]
  end

  test "first and second collected replies have distinct directional time windows" do
    person = Person.resolve_profile!(profile)
    observed([], at: 20.days.ago)
    observed([person], at: 15.days.ago)
    period = Follow::FollowerPeriod.first
    ingest(occurred_at: 14.days.ago)
    ingest(x_id: "7002", occurred_at: 12.days.ago, direction: "incoming")
    ingest(x_id: "7003", occurred_at: 10.days.ago)
    first = period.interaction_window(1)
    second = period.interaction_window(2)
    assert_in_delta 1, first[:minimum_days], 0.001
    assert_in_delta 6, first[:maximum_days], 0.001
    assert_in_delta 3, second[:minimum_days], 0.001
    assert_in_delta 5, period.interaction_window(2, direction: "outgoing")[:minimum_days], 0.001
    assert_nil period.interaction_window(2, direction: "incoming")
    assert_not period.ambiguous_early_replies?
    ingest(x_id: "7004", occurred_at: 17.days.ago)
    assert period.ambiguous_early_replies?
    assert_equal first, period.interaction_window(1)
  end

  test "old snapshots cannot rewrite newer follower periods" do
    person = Person.resolve_profile!(profile)
    observed([person], at: 2.days.ago)
    assert_raises(ArgumentError) { observed([], at: 3.days.ago) }
    assert_equal 1, Follow::FollowerPeriod.ongoing.count
  end
  test "duration bounds include the time spent collecting each snapshot" do
    person = Person.resolve_profile!(profile)
    previous = snapshot("followers", [], observed_at: 20.days.ago)
    previous.update!(completed_at: 19.days.ago)
    Follow::FollowerPeriod.observe!(previous)
    first = snapshot("followers", [person], observed_at: 15.days.ago)
    first.update!(completed_at: 14.days.ago)
    Follow::FollowerPeriod.observe!(first)
    period = Follow::FollowerPeriod.first
    assert_equal first.completed_at, period.first_seen_at
    later = snapshot("followers", [person], observed_at: 10.days.ago)
    later.update!(completed_at: 9.days.ago)
    Follow::FollowerPeriod.observe!(later)
    lost = snapshot("followers", [], observed_at: 5.days.ago)
    lost.update!(completed_at: 4.days.ago)
    Follow::FollowerPeriod.observe!(lost)
    assert_in_delta 4, period.reload.minimum_days, 0.001
    assert_in_delta 16, period.maximum_days, 0.001
  end

end
