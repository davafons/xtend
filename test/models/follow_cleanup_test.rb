require "test_helper"

class FollowCleanupTest < ActiveSupport::TestCase
  test "a post ID dates the latest post, and later sources never move it back" do
    at = Time.utc(2026, 3, 1, 12)
    id = (((at.to_i * 1000) - X::Payload::TWITTER_EPOCH_MS) << 22).to_s
    assert_equal at, X::Payload.snowflake_time(id)
    assert_nil X::Payload.snowflake_time("12")
    row = X::Payload.profile({ "id" => "5", "username" => "quiet", "name" => "Quiet", "most_recent_tweet_id" => id })
    person = Person.resolve_profile!(Person.profile_from_x(row))
    assert_equal at, person.last_posted_at
    older = (((at.to_i - 86_400) * 1000 - X::Payload::TWITTER_EPOCH_MS) << 22).to_s
    Person.resolve_profile!(Person.profile_from_x(X::Payload.profile({ "id" => "5", "username" => "quiet", "name" => "Quiet", "most_recent_tweet_id" => older })))
    assert_equal at, person.reload.last_posted_at
  end

  test "inactive needs a known last post; never interacted needs no signal in any channel" do
    gone, active, unknown, reposted, mutual, kept = %w[1 2 3 4 5 6].map { |id| Person.resolve_profile!(profile(x_id: id, handle: "p#{id}")) }
    gone.update!(last_posted_at: 400.days.ago)
    active.update!(last_posted_at: 2.days.ago)
    mutual.update!(last_posted_at: 300.days.ago)
    kept.update!(last_posted_at: 300.days.ago)
    kept.create_follow_protection!
    X::Interaction.record!(kind: "repost", source: "999", target: "4", post: "77")
    snapshot("following", [ gone, active, unknown, reposted, mutual, kept ])
    snapshot("followers", [ mutual ], observed_at: 3.days.ago)

    cleanup = Follow::Cleanup.new(reason: "inactive")
    assert cleanup.ready?, "including mutuals doesn't need a fresh follower list"
    assert_equal [ gone, mutual ], cleanup.matches
    assert cleanup.mutual?(mutual)
    assert_equal 2, cleanup.unknown_activity_count
    assert_equal [ gone ], Follow::Cleanup.new(reason: "inactive", inactive_days: 365).matches

    strangers = Follow::Cleanup.new(reason: "strangers").matches
    assert_not_includes strangers, reposted, "a captured repost is an interaction"
    assert_not_includes strangers, kept
    assert_equal [ gone, mutual, active, unknown ].map(&:id).sort, strangers.map(&:id).sort

    assert_not Follow::Cleanup.new(mutuals: "0").ready?, "leaving mutuals out needs a fresh follower list"
    snapshot("followers", [ mutual ])
    assert_equal [ gone ], Follow::Cleanup.new(reason: "inactive", mutuals: "0").matches
  end

  test "a following refresh reserves a little more than the last list, within one page" do
    assert_equal 100, X::SyncRun.following_refresh_limit
    snapshot("following", Array.new(120) { |index| Person.resolve_profile!(profile(x_id: (300 + index).to_s, handle: "f#{index}")) })
    assert_equal 182, X::SyncRun.following_refresh_limit
  end
end
