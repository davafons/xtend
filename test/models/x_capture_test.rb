require "test_helper"
require_relative "../test_helpers/web_capture_helper"

class XCaptureTest < ActiveSupport::TestCase
  include WebCaptureHelper

  test "timeline captures keep what was shown and add strangers to the directory, not to People, without any X read" do
    followed = Person.resolve_profile!(profile(x_id: "101", handle: "followed"))
    stranger = web_user("202", "stranger")
    quoted_author = web_user("303", "quoted")
    ad = web_tweet("4004", web_user("404", "advertiser"))
    timeline = web_timeline([
      web_tweet("1001", web_user("101", "followed"), text: "Rails builders: what are you shipping?"),
      web_tweet("2002", stranger, quoted: web_tweet("3003", quoted_author))
    ], promoted: [ ad ])

    result = capture!(web_response("HomeTimeline", timeline))

    assert_equal 0, result[:people_added]
    assert_equal 1, result[:people_updated]
    assert_equal "Builds followed tools", followed.reload.description
    assert_equal [ 120, 80, 900, "Tokyo", "https://followed.dev" ],
      [ followed.followers_count, followed.following_count, followed.posts_count, followed.location, followed.website_url ]
    assert_not Person.exists?(x_id: "202"), "a stranger in the timeline is not a person"
    assert_equal "stranger", X::Account.find_by!(x_id: "202").handle
    assert_not Person.exists?(x_id: "303"), "a quoted author was only context"
    assert_not X::SourcePost.exists?(x_id: "3003"), "a stranger's post quoted by a stranger is only context"
    assert_not X::SourcePost.exists?(x_id: "4004"), "promoted posts are ignored"
    assert_equal %w[1001 2002], X::SourcePost.order(:x_id).pluck(:x_id)
    assert_equal %w[1001], Outreach::Candidate.order(:x_id).pluck(:x_id)
    assert_equal [ "x_capture" ], Outreach::Candidate.distinct.pluck(:source)
    assert_equal 0, X::Read.count
    assert_empty X::SyncRun.unresolved_user_ids
    assert_empty X::SyncRun.unresolved_parent_ids
  end

  test "threads record the owner's reply exchanges but not strangers talking to strangers" do
    owner = owner_user
    author = web_user("501", "author")
    bystander = web_user("502", "bystander")
    fan = web_user("503", "fan")
    root = web_tweet("5000", author, text: "What's your stack?")
    detail = { "data" => { "threaded_conversation_with_injections_v2" => { "instructions" => [ { "entries" => [
      root,
      web_tweet("5001", bystander, reply_to: { post: "5000", user: "501" }),
      web_tweet("5002", owner, text: "Rails and SQLite", reply_to: { post: "5000", user: "501" }),
      web_tweet("5003", fan, text: "Same here", reply_to: { post: "5002", user: owner["rest_id"], conversation: "5000" })
    ] } ] } } }

    capture!(web_response("TweetDetail", detail))

    assert Person.exists?(x_id: "501")
    assert Person.exists?(x_id: "503")
    assert_not Person.exists?(x_id: "502")
    outgoing = ReplyEvent.find_by!(x_id: "5002")
    assert_equal [ "outgoing", "initial", "x_capture" ], [ outgoing.direction, outgoing.classification, outgoing.source ]
    assert_equal "author", outgoing.person.handle
    assert ReplyEvent.exists?(x_id: "5003", direction: "incoming", source: "x_capture")
    assert_equal 0, Outreach::Candidate.count, "thread context is not a reply target"
  end

  test "only the owner's Likes page records likes, and capture never claims like coverage" do
    liked = web_tweet("6001", web_user("601", "liked"))
    capture!(web_response("Likes", web_timeline([ liked ]), variables: { "userId" => Current.workspace.owner_x_id }))
    capture!(web_response("Likes", web_timeline([ web_tweet("6002", web_user("602", "theirs")) ]), variables: { "userId" => "123" }))
    capture!(web_response("Bookmarks", web_timeline([ web_tweet("6003", web_user("603", "saved")) ])))

    assert_equal [ "6001" ], Engagement.where(kind: "like").pluck(:post_x_id)
    assert_equal [ "6003" ], Engagement.where(kind: "bookmark").pluck(:post_x_id)
    assert Person.exists?(x_id: "601")
    assert_not Person.exists?(x_id: "602")
    assert_nil Engagement.coverage("like")[:checked_at]
  end

  test "re-sending a batch is harmless and manual choices survive" do
    person = Person.resolve_profile!(profile(x_id: "701", handle: "kept"))
    person.update!(notes: "Met at RubyKaigi")
    person.create_pin!
    batch = web_response("HomeTimeline", web_timeline([ web_tweet("7001", web_user("701", "kept")) ]))

    capture!(batch, batch_key: "batch-key-000000001")
    capture!(batch, batch_key: "batch-key-000000001")
    capture!(batch, batch_key: "batch-key-000000002")

    assert_equal 1, Person.where(x_id: "701").count
    assert_equal 1, Outreach::Candidate.where(x_id: "7001").count
    assert_equal "Met at RubyKaigi", person.reload.notes
    assert person.pin.present?
  end

  test "an API read takes over a captured post so mention coverage stays honest" do
    capture!(web_response("TweetDetail", { "data" => [ web_tweet("8001", web_user("801", "fan"), reply_to: { post: "8000", user: Current.workspace.owner_x_id }) ] }))
    run = X::SyncRun.create!(dataset: "mentions", owner_x_id: Current.workspace.owner_x_id, request_key: SecureRandom.uuid,
      mode: "refresh", page_limit: 10, upper_bound: Time.current)
    row = { "id" => "8001", "author_id" => "801", "text" => "hi", "created_at" => 1.hour.ago.iso8601,
      "referenced_posts" => [ { "id" => "8000", "type" => "replied_to" } ] }
    X::SourcePost.capture!(row, run: run)

    assert_equal run, X::SourcePost.find_by!(x_id: "8001").x_sync_run
  end

  test "both profile layouts parse and malformed items are skipped" do
    broken = { "__typename" => "Tweet", "rest_id" => "9002", "legacy" => { "full_text" => "no date" } }
    result = capture!(web_response("SearchTimeline", web_timeline([ web_tweet("9001", web_user("901", "legacy_layout", layout: :legacy)), broken ])))

    assert_equal "legacy_layout", X::Account.find_by!(x_id: "901").handle
    assert_equal 1, result[:skipped]
    assert_equal 1, result[:posts]
  end

  test "batches from another X account or unknown operations are refused or ignored" do
    error = assert_raises(X::Capture::Rejected) { capture!(web_response("HomeTimeline", web_timeline([])), viewer: "12345") }
    assert_match "different X account", error.message

    result = capture!({ "operation" => "DMInbox", "body" => "{}" })
    assert_equal 1, result[:ignored]
  end

  test "posts keep counts, media, and links, and each sighting is observed once per surface and hour" do
    Person.resolve_profile!(profile(x_id: "111", handle: "builder"))
    tweet = web_tweet("1101", web_user("111", "builder"), likes: 42, views: "9000", media: %w[photo photo video], urls: [ "https://example.com/post" ])
    batch = web_response("HomeTimeline", web_timeline([ tweet ]))

    capture!(batch)
    capture!(batch)
    capture!(web_response("UserTweets", web_timeline([ web_tweet("1101", web_user("111", "builder"), likes: 50) ])))

    post = X::SourcePost.find_by!(x_id: "1101")
    assert_equal [ 50, 3, 1, 4, 1500, "photo,video", true ], [ post.like_count, post.repost_count, post.quote_count, post.bookmark_count, post.view_count, post.media_kinds, post.has_link ]
    assert_equal({ "home" => 42, "profile" => 50 }, X::PostObservation.where(post_x_id: "1101").pluck(:surface, :like_count).to_h)
    travel 1.hour do
      capture!(batch)
      assert_equal 3, X::PostObservation.where(post_x_id: "1101").count
    end
  end

  test "posts keep what to draw for their photos, videos, and GIFs, only from X's own hosts" do
    Person.resolve_profile!(profile(x_id: "111", handle: "builder"))
    photo = { "type" => "photo", "media_url_https" => "https://pbs.twimg.com/media/A1.jpg", "ext_alt_text" => "A desk",
      "original_info" => { "width" => 1200, "height" => 800 } }
    video = { "type" => "video", "media_url_https" => "https://pbs.twimg.com/ext_tw_video_thumb/1/pu/img/B2.jpg",
      "video_info" => { "variants" => [
        { "content_type" => "application/x-mpegURL", "url" => "https://video.twimg.com/ext_tw_video/1/pu/pl/B2.m3u8" },
        { "content_type" => "video/mp4", "bitrate" => 256_000, "url" => "https://video.twimg.com/ext_tw_video/1/pu/vid/480x270/low.mp4?tag=12" },
        { "content_type" => "video/mp4", "bitrate" => 2_176_000, "url" => "https://video.twimg.com/ext_tw_video/1/pu/vid/1280x720/high.mp4?tag=12" } ] } }
    elsewhere = { "type" => "animated_gif", "media_url_https" => "https://evil.example/gif.jpg" }
    capture!(web_response("HomeTimeline", web_timeline([ web_tweet("1102", web_user("111", "builder"), media: [ photo, video, elsewhere ]) ])))
    capture!(web_response("UserTweets", web_timeline([ web_tweet("1102", web_user("111", "builder")) ])))

    post = X::SourcePost.find_by!(x_id: "1102")
    assert_equal "animated_gif,photo,video", post.media_kinds
    assert_equal [
      { "kind" => "photo", "image" => "https://pbs.twimg.com/media/A1.jpg", "alt" => "A desk", "width" => 1200, "height" => 800 },
      { "kind" => "video", "image" => "https://pbs.twimg.com/ext_tw_video_thumb/1/pu/img/B2.jpg",
        "video" => "https://video.twimg.com/ext_tw_video/1/pu/vid/1280x720/high.mp4?tag=12" }
    ], post.media, "the best MP4 is kept, a sighting without media keeps it, and other hosts are dropped"
  end

  test "replies, quotes, reposts, and body mentions become interactions; strangers talking to strangers don't" do
    owner = owner_user
    alice = web_user("121", "alice")
    bob = web_user("122", "bob")
    [ alice, bob ].each { |user| Person.resolve_profile!(Person.profile_from_x(X::Payload.profile("id" => user["rest_id"], "username" => user.dig("core", "screen_name")))) }
    carol = web_user("123", "carol")
    dave = web_user("124", "dave")
    root = web_tweet("1200", alice, text: "What are you building?")
    detail = { "data" => { "threaded_conversation_with_injections_v2" => { "instructions" => [ { "entries" => [
      root,
      web_tweet("1201", bob, text: "A CRM", reply_to: { post: "1200", user: "121" }, leading_mentions: [ alice ], mentions: [ carol ]),
      web_tweet("1202", carol, text: "Nice", reply_to: { post: "1201", user: "122", conversation: "1200" }),
      web_tweet("1203", dave, text: "Spam", reply_to: { post: "1202", user: "123", conversation: "1200" })
    ] } ] } } }
    capture!(web_response("TweetDetail", detail))
    capture!(web_response("HomeTimeline", web_timeline([
      web_tweet("1204", bob, text: "This", quoted: root),
      web_tweet("1205", owner, text: "", reposted: web_tweet("1201", bob, text: "A CRM"))
    ])))

    edges = X::Interaction.order(:post_x_id, :kind).pluck(:kind, :source_x_id, :target_x_id, :post_x_id)
    assert_includes edges, [ "reply", "122", "121", "1201" ]
    assert_includes edges, [ "mention", "122", "123", "1201" ]
    assert_includes edges, [ "reply", "123", "122", "1202" ]
    assert_includes edges, [ "quote", "122", "121", "1204" ]
    assert_includes edges, [ "repost", Current.workspace.owner_x_id, "122", "1205" ]
    assert_not edges.any? { |edge| edge[1] == "124" }, "a stranger replying to a stranger is dropped"
    assert_not edges.include?([ "mention", "122", "121", "1201" ]), "the reply chain's leading @handle is not a mention"
    assert_not Person.exists?(x_id: "123")
  end

  test "engagement and follow lists add likes, reposts, and follow edges" do
    Current.workspace.update!(owner_x_id: Current.workspace.owner_x_id)
    fans = [ web_user("131", "fan_one"), web_user("132", "fan_two") ]
    capture!(web_response("Favoriters", web_user_list(fans), variables: { "tweetId" => "1300" }))
    capture!(web_response("TweetDetail", { "data" => [ web_tweet("1301", web_user("133", "author")) ] }),
      web_response("Retweeters", web_user_list([ fans.first ]), variables: { "tweetId" => "1301" }))
    capture!(web_response("Following", web_user_list(fans), variables: { "userId" => "133" }))
    capture!(web_response("FollowersYouKnow", web_user_list([ fans.last ]), variables: { "userId" => "131" }))

    owner = Current.workspace.owner_x_id
    assert_equal [ [ "131", owner ], [ "132", owner ] ], X::Interaction.where(kind: "like").order(:source_x_id).pluck(:source_x_id, :target_x_id)
    assert_equal [ [ "131", "133" ] ], X::Interaction.where(kind: "repost").pluck(:source_x_id, :target_x_id)
    assert_equal [ [ "132", "131" ], [ "133", "131" ], [ "133", "132" ] ], X::FollowEdge.order(:follower_x_id, :followed_x_id).pluck(:follower_x_id, :followed_x_id)
    assert_equal 3, X::Account.where(x_id: %w[131 132 133]).count
    assert_not Person.exists?(x_id: "131")
  end

  test "accounts x.com shows correct the follow snapshot person by person, and only newer sightings count" do
    kept = Person.resolve_profile!(profile(x_id: "141", handle: "kept"))
    gone = Person.resolve_profile!(profile(x_id: "142", handle: "gone"))
    unseen = Person.resolve_profile!(profile(x_id: "143", handle: "unseen"))
    snapshot("following", [ kept, gone, unseen ], observed_at: 2.days.ago)
    snapshot("followers", [ kept ], observed_at: 2.days.ago)
    now = (Time.current.to_f * 1000).to_i
    still = web_user("141", "kept").merge("relationship_perspectives" => { "following" => true, "followed_by" => false })
    dropped = web_user("142", "gone").merge("relationship_perspectives" => { "following" => false, "followed_by" => false })
    new_follow = web_user("144", "fresh").merge("relationship_perspectives" => { "following" => true, "followed_by" => true })
    stranger = web_user("145", "stranger").merge("relationship_perspectives" => { "following" => false, "followed_by" => false })
    timeline = web_timeline(%w[141 142 144 145].zip([ still, dropped, new_follow, stranger ]).map { |id, user| web_tweet("1#{id}0", user) })

    result = capture!(web_response("HomeTimeline", timeline).merge("at" => now))
    stale = web_user("142", "gone").merge("relationship_perspectives" => { "following" => true })
    capture!(web_response("UserByScreenName", { "data" => { "user" => { "result" => stale } } }).merge("at" => now - 60_000))

    graph = Follow::Graph.latest
    fresh = Person.find_by!(x_id: "144")
    assert_equal 3, result[:relationships], "strangers you neither follow nor are followed by aren't tracked"
    assert graph.following?(kept)
    assert_not graph.following?(gone), "a newer sighting overrides the snapshot, and an older one can't undo it"
    assert graph.following?(unseen), "people the capture didn't see keep the snapshot's answer"
    assert graph.following?(fresh), "someone you follow becomes a person"
    assert graph.follower?(fresh)
    assert_not graph.follower?(kept), "an unfollow back shows up too"
    assert_not Person.exists?(x_id: "145"), "a stranger you don't follow stays out of People"
  end

  test "an unfollow click on x.com records the review, and a follow click adds the person" do
    target = Person.resolve_profile!(profile(x_id: "151", handle: "target"))
    snapshot("following", [ target ], observed_at: 1.day.ago)
    user = web_user("152", "newbie", layout: :legacy)["legacy"].merge("id_str" => "152", "following" => false)

    result = capture!(
      web_response("FollowDestroy", web_user("151", "target", layout: :legacy)["legacy"].merge("id_str" => "151", "following" => true), variables: { "user_id" => "151" }),
      web_response("FollowCreate", user, variables: { "user_id" => "152" }))

    graph = Follow::Graph.latest
    assert_equal 1, result[:unfollows]
    assert_not graph.following?(target), "the answer's stale following field doesn't count"
    assert_equal "unfollowed", Follow::Review.find_by!(person: target).decision
    assert_not_includes Follow::Cleanup.new.eligible, target
    newbie = Person.find_by!(x_id: "152")
    assert graph.following?(newbie)
    assert X::FollowEdge.exists?(follower_x_id: Current.workspace.owner_x_id, followed_x_id: "152")
  end

  test "posts x.com marks as liked, reposted, or bookmarked by you count as your actions" do
    liked = web_tweet("1601", web_user("161", "liked"))
    liked["legacy"].merge!("favorited" => true, "bookmarked" => true)
    reposted = web_tweet("1602", web_user("162", "reposted"))
    reposted["legacy"]["retweeted"] = true
    plain = web_tweet("1603", web_user("163", "plain"))
    plain["legacy"].merge!("favorited" => false, "retweeted" => false)
    capture!(web_response("HomeTimeline", web_timeline([ liked, reposted, plain ])))
    later = web_tweet("1604", web_user("164", "later"))
    capture!(web_response("HomeTimeline", web_timeline([ later ])))
    capture!(web_response("FavoriteTweet", { "data" => { "favorite_tweet" => "Done" } }, variables: { "tweet_id" => "1604" }))

    owner = Current.workspace.owner_x_id
    assert_equal %w[1601 1604], Engagement.where(kind: "like").order(:post_x_id).pluck(:post_x_id)
    assert_equal %w[1601], Engagement.where(kind: "bookmark").pluck(:post_x_id)
    assert X::Interaction.exists?(kind: "repost", source_x_id: owner, target_x_id: "162")
    assert_not X::Interaction.exists?(source_x_id: owner, target_x_id: "163")
  end

  test "a reply you post is recorded as soon as x.com confirms it" do
    author = web_user("171", "author")
    capture!(web_response("TweetDetail", web_timeline([ web_tweet("1700", author) ])))
    reply = web_tweet("1701", owner_user, text: "Nice one", reply_to: { post: "1700", user: "171" })

    capture!(web_response("CreateTweet", { "data" => { "create_tweet" => { "tweet_results" => { "result" => reply } } } }))

    event = ReplyEvent.find_by!(x_id: "1701")
    assert_equal [ "outgoing", "author" ], [ event.direction, event.person.handle ]
  end
  test "post text reads as x.com shows it: real links, no media or quote links, no escapes, full long posts, article titles" do
    author = web_user("181", "writer")
    quoted = web_tweet("1810", web_user("182", "quoted"))
    plain = web_tweet("1801", author, text: "Rails &amp; SQLite &gt; everything https://t.co/link1 https://t.co/quote1 https://t.co/media1", quoted: quoted)
    plain["legacy"]["entities"]["urls"] = [ { "url" => "https://t.co/link1", "expanded_url" => "https://rubyonrails.org" },
      { "url" => "https://t.co/quote1", "expanded_url" => "https://twitter.com/quoted/status/1810" } ]
    plain["legacy"]["entities"]["media"] = [ { "url" => "https://t.co/media1", "type" => "photo" } ]
    long = web_tweet("1802", author, text: "Start of a long post…")
    friend = web_user("183", "friend")
    long["note_tweet"] = { "note_tweet_results" => { "result" => { "text" => "Start of a long post, and later thanks @friend https://t.co/late1",
      "entity_set" => { "user_mentions" => [ { "id_str" => "183", "indices" => [ 39, 46 ] } ],
        "urls" => [ { "url" => "https://t.co/late1", "expanded_url" => "https://example.com/late" } ] } } } }
    article = web_tweet("1803", author, text: "https://t.co/article1")
    article["article"] = { "article_results" => { "result" => { "title" => "How I ship", "preview_text" => "Ten people, one Rails app." } } }
    photo = web_tweet("1804", author, text: "https://t.co/media2")
    photo["legacy"]["entities"]["media"] = [ { "url" => "https://t.co/media2", "expanded_url" => "https://x.com/writer/status/1804/photo/1", "type" => "photo" } ]

    capture!(web_response("HomeTimeline", web_timeline([ plain, long, article, photo ])))

    assert_equal [ "Rails & SQLite > everything https://rubyonrails.org",
      "Start of a long post, and later thanks @friend https://example.com/late", "How I ship\n\nTen people, one Rails app.",
      "https://x.com/writer/status/1804/photo/1" ], X::SourcePost.where(x_id: %w[1801 1802 1803 1804]).order(:x_id).pluck(:body)
    assert X::SourcePost.find_by!(x_id: "1802").has_link, "a link past 280 characters still counts"
    assert X::Interaction.exists?(kind: "mention", source_x_id: "181", target_x_id: "183"), "so does a mention"
  end
end
