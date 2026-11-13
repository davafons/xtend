require "test_helper"
require_relative "../test_helpers/web_capture_helper"

class CleanupAndInboxTest < ActiveSupport::TestCase
  include WebCaptureHelper

  test "cleanup shows each candidate's latest own posts, filters by tag, and can put off-topic accounts first" do
    a, b, c = %w[11 12 13].map { |id| Person.resolve_profile!(profile(x_id: id, handle: "p#{id}")) }
    snapshot("following", [ a, b, c ])
    capture!(web_response("UserTweets", web_timeline([
      web_tweet("1101", web_user("11", "p11"), text: "oldest", created: 3.days.ago),
      web_tweet("1102", web_user("11", "p11"), text: "middle", created: 2.days.ago),
      web_tweet("1103", web_user("11", "p11"), text: "newest", created: 1.day.ago)
    ])))
    b.add_tags!("off-topic")
    c.add_tags!("rails")

    cleanup = Follow::Cleanup.new(reason: "strangers", sort: "off_topic")
    assert_equal %w[newest middle], cleanup.recent_posts([ a, b ])["11"].map(&:body)
    assert_equal b, cleanup.candidates(3).first
    assert_equal [ c ], Follow::Cleanup.new(reason: "strangers", tag: "Rails").matches
    assert_equal [ a ], Follow::Cleanup.new(reason: "strangers", tag: "untagged").matches
    assert_equal %w[off-topic rails], cleanup.tag_options.sort

    prompt = Grok::Classification.relevance_prompt([ a ])
    assert_includes prompt, "off-topic"
    assert_includes prompt, Current.workspace.interests.first
    assert_includes prompt, "p11"
  end

  test "progress counts an unfollow once even when the capture later confirms a reported one" do
    a, b = %w[21 22].map { |id| Person.resolve_profile!(profile(x_id: id, handle: "p#{id}")) }
    travel_to(2.days.ago) { Follow::Review.record!(a, "reported_unfollow") }
    Follow::Review.record!(a, "unfollowed")
    Follow::Review.record!(b, "keep")

    days = Follow::Progress.new.decisions
    assert_equal 3, days.size
    assert_equal [ 1, 0 ], days.first.drop(1)
    assert_equal [ 0, 1 ], days.last.drop(1)
  end

  test "follower changes list gains and losses between complete lists, plus what x.com showed since" do
    stays, leaves, arrives, sighted = %w[31 32 33 34].map { |id| Person.resolve_profile!(profile(x_id: id, handle: "p#{id}")) }
    Follow::FollowerPeriod.observe!(snapshot("followers", [ stays, leaves ], observed_at: 3.days.ago))
    Follow::FollowerPeriod.observe!(snapshot("followers", [ stays, arrives ], observed_at: 1.day.ago))
    stays.update_columns(follows_you: false, follows_you_seen_at: 1.hour.ago)
    sighted.update_columns(follows_you: true, follows_you_seen_at: 1.hour.ago)

    changes = Follow::FollowerChanges.new
    assert_equal [ [ "p32", :lost ], [ "p33", :gained ] ], changes.changes.map { |change| [ change.person.handle, change.kind ] }.sort
    assert_equal [ [ "p31", :lost ], [ "p34", :gained ] ], changes.sightings.map { |sighting| [ sighting.person.handle, sighting.kind ] }.sort
  end

  test "replies to you wait until you answer them directly or later in the thread, or set them aside" do
    owner = owner_user
    fan, friend, other = web_user("41", "fan"), web_user("42", "friend"), web_user("43", "other")
    mine = web_tweet("4000", owner, text: "Shipping today")
    capture!(web_response("TweetDetail", web_timeline([
      mine,
      web_tweet("4001", fan, text: "Nice!", reply_to: { post: "4000", user: owner["rest_id"] }, created: 50.minutes.ago),
      web_tweet("4002", friend, text: "How?", reply_to: { post: "4000", user: owner["rest_id"] }, created: 40.minutes.ago),
      web_tweet("4003", owner, text: "Like this", reply_to: { post: "4002", user: "42", conversation: "4000" }, created: 30.minutes.ago),
      web_tweet("4004", other, text: "Cool", reply_to: { post: "4000", user: owner["rest_id"] }, created: 20.minutes.ago)
    ])))

    inbox = ReplyInbox.new
    assert_equal %w[other fan], inbox.items.map { |item| item.person.handle }
    ReplyEvent.find_by!(x_id: "4004").update!(dismissed_at: Time.current)
    assert_equal %w[fan], ReplyInbox.new.items.map { |item| item.person.handle }
  end

  test "a reply to your answer is a follow-up, but a reply to your outreach still waits" do
    owner = owner_user
    friend, builder = web_user("42", "friend"), web_user("44", "builder")
    capture!(web_response("TweetDetail", web_timeline([
      web_tweet("4000", owner, text: "Shipping today"),
      web_tweet("4002", friend, text: "How?", reply_to: { post: "4000", user: owner["rest_id"] }, created: 40.minutes.ago),
      web_tweet("4003", owner, text: "Like this", reply_to: { post: "4002", user: "42", conversation: "4000" }, created: 30.minutes.ago),
      web_tweet("4005", friend, text: "Thanks!", reply_to: { post: "4003", user: owner["rest_id"], conversation: "4000" }, created: 20.minutes.ago)
    ])))
    capture!(web_response("TweetDetail", web_timeline([
      web_tweet("5000", builder, text: "My first launch", created: 2.hours.ago),
      web_tweet("5001", owner, text: "Congrats!", reply_to: { post: "5000", user: "44" }, created: 90.minutes.ago),
      web_tweet("5002", builder, text: "Thank you!", reply_to: { post: "5001", user: owner["rest_id"], conversation: "5000" }, created: 80.minutes.ago)
    ])))

    assert_equal %w[builder], ReplyInbox.new.items.map { |item| item.person.handle }
    assert_equal %w[friend], ReplyInbox.new(follow_ups: true).items.map { |item| item.person.handle }
    assert_equal [ 1, 1 ], ReplyInbox.new.then { |inbox| [ inbox.waiting_count, inbox.follow_up_count ] }
  end
end
