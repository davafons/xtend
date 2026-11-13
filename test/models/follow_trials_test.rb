require "test_helper"
require_relative "../test_helpers/web_capture_helper"

class FollowTrialsTest < ActiveSupport::TestCase
  include WebCaptureHelper

  test "trials cover follows after the first list, with follow-back and a due date" do
    old, back, silent, fresh, kept, reported = %w[61 62 63 64 65 66].map { |id| Person.resolve_profile!(profile(x_id: id, handle: "p#{id}")) }
    snapshot("following", [ old ], observed_at: 50.days.ago)
    snapshot("following", [ old, back, silent, kept, reported ], observed_at: 40.days.ago)
    Follow::FollowerPeriod.observe!(snapshot("followers", [ back ], observed_at: 1.hour.ago))
    kept.create_follow_protection!
    Follow::Review.record!(reported, "reported_unfollow")
    capture!(web_response("FollowCreate", web_user("64", "p64", layout: :legacy)["legacy"].merge("id_str" => "64"), variables: { "user_id" => "64" }))

    trials = Follow::Trials.new(days: 30)
    assert_equal %w[p62 p63 p64 p65], trials.all.map { |trial| trial.person.handle }.sort, "the first list is a baseline; a reported unfollow leaves"
    assert_equal %w[p63], trials.due.map { |trial| trial.person.handle }
    assert_equal %w[p62], trials.followed_back.map { |trial| trial.person.handle }
    assert_equal %w[p64], trials.waiting.map { |trial| trial.person.handle }
    silent_trial = trials.all.find { |trial| trial.person == silent }
    assert_equal 50.days.ago.to_date, silent_trial.after.to_date
    assert_equal 40, silent_trial.days
  end

  test "a capture batch announces itself for open pages, and the status says what it added" do
    capture!(web_response("HomeTimeline", web_timeline([ web_tweet("7001", web_user("71", "someone")) ])))
    workspace = Current.workspace.reload
    assert workspace.captured_at
    assert_equal 1, workspace.last_capture["posts"]
    summary = ApplicationController.helpers.capture_summary({ "posts" => 3, "lists" => [ { "direction" => "following", "state" => "partial", "seen" => 40, "expected" => 500 } ] })
    assert_equal "following list 40 of 500 so far · 3 posts", summary

    before = workspace.captured_at
    capture!
    assert_equal before, Current.workspace.reload.captured_at, "the extension's connection test isn't news"
  end
end
