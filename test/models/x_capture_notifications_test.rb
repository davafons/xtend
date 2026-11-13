require "test_helper"
require_relative "../test_helpers/web_capture_helper"

class XCaptureNotificationsTest < ActiveSupport::TestCase
  include WebCaptureHelper

  setup do
    @owner = Current.workspace.owner_x_id
  end

  def relation(user, following:, followed_by:)
    user.merge("relationship_perspectives" => { "following" => following, "followed_by" => followed_by, "blocking" => false, "muting" => false })
  end

  def notifications(*entries, at: nil)
    response = web_response("NotificationsTimeline", web_notifications(*entries), variables: { "timeline_type" => "All", "count" => 20 })
    at ? response.merge("at" => at) : response
  end

  test "likes and reposts of your posts become interactions timed by the notification, even when grouped" do
    mine = web_tweet("9001", owner_user, created: 3.days.ago)
    reply = web_tweet("9002", owner_user, text: "Thanks!", created: 2.days.ago)
    fans = [ web_user("901", "fan_one"), web_user("902", "fan_two"), web_user("903", "fan_three") ]
    grouped_at = Time.utc(2026, 11, 12, 13, 54, 12)
    single_at = Time.utc(2026, 11, 9, 5, 55, 35)

    result = capture!(notifications(
      web_notification("users_liked_your_tweet", fans, posts: [ mine ], at: grouped_at),
      web_notification("users_liked_your_tweet", [ fans.first ], posts: [ reply ], at: single_at),
      web_notification("users_retweeted_your_tweet", [ fans.last ], posts: [ mine ], at: single_at, icon: "retweet_icon"),
      web_notification("user_liked_multiple_tweets", [ fans[1] ], posts: [ reply ], at: single_at)))

    likes = X::Interaction.where(kind: "like").order(:source_x_id, :post_x_id).pluck(:source_x_id, :target_x_id, :post_x_id, :occurred_at)
    assert_equal [
      [ "901", @owner, "9001", grouped_at ], [ "901", @owner, "9002", single_at ],
      [ "902", @owner, "9001", grouped_at ], [ "902", @owner, "9002", single_at ],
      [ "903", @owner, "9001", grouped_at ]
    ], likes
    assert_equal [ [ "903", @owner, "9001" ] ], X::Interaction.where(kind: "repost").pluck(:source_x_id, :target_x_id, :post_x_id)
    assert_equal 4, result[:notifications]
    assert_equal %w[9001 9002], X::SourcePost.order(:x_id).pluck(:x_id), "your liked posts are kept with their counts"
    assert_equal 3, X::Account.where(x_id: %w[901 902 903]).count
    assert_not Person.exists?(x_id: "901"), "a like from a stranger doesn't make them a person"
    signal = Person::Interactions.for(Person.resolve_profile!(profile(x_id: "903", handle: "fan_three"))).signals.find { |s| s.channel == "repost" }
    assert_equal [ single_at, "incoming" ], [ signal.at, signal.direction ]
  end

  test "new followers get a follow edge dated by X, become people, and show on their timeline" do
    newcomer = relation(web_user("911", "newcomer"), following: false, followed_by: true)
    mutual = relation(web_user("912", "mutual"), following: true, followed_by: true)
    gone = relation(web_user("913", "gone"), following: false, followed_by: false)
    followed_at = Time.utc(2026, 10, 26, 21, 56, 26)

    result = capture!(notifications(
      web_notification("users_followed_you", [ newcomer, mutual, gone ], at: followed_at, icon: "person_icon"),
      web_notification("follow_from_recommended_user", [ relation(web_user("914", "recommended"), following: false, followed_by: true) ], at: followed_at - 1.day, icon: "person_icon")))

    edges = X::FollowEdge.where(followed_x_id: @owner).order(:follower_x_id).pluck(:follower_x_id, :followed_at)
    assert_equal [ [ "911", followed_at ], [ "912", followed_at ], [ "914", followed_at - 1.day ] ], edges
    assert_equal 3, result[:follows]
    assert_not X::FollowEdge.exists?(follower_x_id: "913"), "someone who no longer follows you gets no edge"
    newcomer_person = Person.find_by!(x_id: "911")
    assert newcomer_person.follows_you
    entry = Person::Timeline.new(newcomer_person).entries.find { |e| e.category == "follows" }
    assert_equal [ followed_at, "Followed you" ], [ entry.at, entry.title ]
  end

  test "a follow notification dates a follower period that complete lists could only bound" do
    person = Person.resolve_profile!(profile(x_id: "921", handle: "follower"))
    Follow::FollowerPeriod.observe!(snapshot("followers", [], observed_at: 20.days.ago))
    Follow::FollowerPeriod.observe!(snapshot("followers", [ person ], observed_at: 2.days.ago))
    followed_at = 10.days.ago.change(usec: 0)

    capture!(notifications(web_notification("users_followed_you", [ relation(web_user("921", "follower"), following: false, followed_by: true) ], at: followed_at)))

    follows = Person::Timeline.new(person).entries.select { |e| e.category == "follows" }
    assert_equal [ [ followed_at, "Started following you" ] ], follows.map { |e| [ e.at, e.title ] }
    assert_match "from your X notifications", follows.first.detail
  end

  test "replies and mentions are saved as posts, and other notifications or other people's posts add nothing" do
    stranger_post = web_tweet("9301", web_user("931", "someone"))
    fan = web_user("932", "fan")
    replier = web_user("933", "replier")
    mine = web_tweet("9300", owner_user, created: 2.days.ago)
    reply = web_tweet("9302", replier, text: "Great point", reply_to: { post: "9300", user: @owner })
    mention = web_tweet("9303", web_user("934", "mentioner"), text: "Ask", mentions: [ owner_user ])

    result = capture!(notifications(
      web_notification_post("user_replied_to_your_tweet", reply),
      web_notification_post("user_mentioned_you", mention),
      web_notification("users_liked_your_tweet", [ fan ], posts: [ stranger_post ]),
      web_notification("device_follow_tweet_notification_entry", [ fan ], icon: "bell_icon"),
      { "entryId" => "notification-archive", "content" => { "clientEventInfo" => { "element" => "generic_zipbird_success_notification" },
        "itemContent" => { "__typename" => "TimelineNotification", "rich_message" => { "text" => "Your X archive is ready" }, "template" => { "from_users" => [], "target_objects" => [] } } } }),
      web_response("TweetDetail", web_timeline([ mine ])))

    assert X::SourcePost.exists?(x_id: "9302")
    assert X::SourcePost.exists?(x_id: "9303")
    assert ReplyEvent.exists?(x_id: "9302", direction: "incoming"), "a reply to you is a reply exchange"
    assert X::Interaction.exists?(kind: "mention", source_x_id: "934", target_x_id: @owner)
    assert_not X::Interaction.exists?(kind: "like"), "a like on someone else's post isn't yours"
    assert_equal 1, result[:notifications]
    assert_equal [ "notifications" ], X::PostObservation.where(post_x_id: "9302").pluck(:surface)
  end

  test "re-sending notifications is harmless and a newer follow after an unfollow wins" do
    user = relation(web_user("941", "returning"), following: false, followed_by: true)
    first = Time.utc(2026, 9, 1)
    second = Time.utc(2026, 10, 1)
    capture!(notifications(web_notification("users_followed_you", [ user ], at: second)))
    capture!(notifications(web_notification("users_followed_you", [ user ], at: first)))
    capture!(notifications(web_notification("users_liked_your_tweet", [ user ], posts: [ web_tweet("9401", owner_user) ])))
    capture!(notifications(web_notification("users_liked_your_tweet", [ user ], posts: [ web_tweet("9401", owner_user) ])))

    edge = X::FollowEdge.find_by!(follower_x_id: "941", followed_x_id: @owner)
    assert_equal [ second, first ], [ edge.followed_at, edge.first_seen_at ]
    assert_equal 1, X::Interaction.where(kind: "like", source_x_id: "941").count
  end

  test "renamed profile tabs, profile batches, and hover-card follow lists are captured" do
    author = web_user("951", "author")
    replies = web_timeline([ web_tweet("9501", author, text: "A reply", reply_to: { post: "1", user: "952" }) ])
    reposts = web_timeline([ web_tweet("9502", author, reposted: web_tweet("9503", web_user("953", "original"))) ])
    batch = { "data" => { "users" => [ { "result" => web_user("954", "batched") } ] } }
    friend = web_user("955", "friend", layout: :legacy)["legacy"].merge("id_str" => "955", "following" => true, "followed_by" => false)
    hover = { "users" => [ friend ], "next_cursor" => 0, "next_cursor_str" => "0", "total_count" => 78 }

    capture!(web_response("UserRepliesTimeline", replies, variables: { "userId" => "951" }),
      web_response("UserRepostsTimeline", reposts, variables: { "userId" => "951" }),
      web_response("UsersByRestIds", batch, variables: { "userIds" => [ "954" ] }),
      web_response("FollowingFollowers", hover, variables: { "userId" => "951" }))

    assert X::SourcePost.where(x_id: %w[9501 9502]).count == 2
    assert_equal [ "discovery" ], X::SourcePost.where(x_id: "9501").joins(:x_sync_run).pluck(Arel.sql("json_extract(x_sync_runs.parameters, '$.purpose')"))
    assert X::Interaction.exists?(kind: "repost", source_x_id: "951", target_x_id: "953")
    assert_equal [ "profile" ], X::PostObservation.where(post_x_id: "9501").pluck(:surface)
    assert X::Account.exists?(x_id: "954")
    assert X::FollowEdge.exists?(follower_x_id: "955", followed_x_id: "951", seen_on: "FollowingFollowers")
    assert Person.find_by!(x_id: "955").you_follow, "the hover card says you follow them"
  end
end
