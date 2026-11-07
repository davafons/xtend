require "test_helper"
require_relative "../test_helpers/web_capture_helper"

class XCaptureTest < ActiveSupport::TestCase
  include WebCaptureHelper

  test "timeline captures add listed authors and discovery posts without any X read" do
    followed = Person.resolve_profile!(profile(x_id: "101", handle: "followed"))
    stranger = web_user("202", "stranger")
    quoted_author = web_user("303", "quoted")
    ad = web_tweet("4004", web_user("404", "advertiser"))
    timeline = web_timeline([
      web_tweet("1001", web_user("101", "followed"), text: "Rails builders: what are you shipping?"),
      web_tweet("2002", stranger, quoted: web_tweet("3003", quoted_author))
    ], promoted: [ ad ])

    result = capture!(web_response("HomeTimeline", timeline))

    assert_equal 1, result[:people_added]
    assert_equal 1, result[:people_updated]
    assert_equal "Builds followed tools", followed.reload.description
    assert_equal [ 120, 80, 900, "Tokyo", "https://followed.dev" ],
      [ followed.followers_count, followed.following_count, followed.posts_count, followed.location, followed.website_url ]
    assert Person.exists?(x_id: "202")
    assert_not Person.exists?(x_id: "303"), "a quoted author was only context"
    assert_not Person.exists?(x_id: "404"), "promoted posts are ignored"
    assert_equal %w[1001 2002], Post.order(:x_id).pluck(:x_id)
    assert_equal [ "x_capture" ], Post.distinct.pluck(:source)
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
    assert_equal 0, Post.count, "thread context is not a reply target"
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
    assert_equal 1, Post.where(x_id: "7001").count
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

    assert_equal "legacy_layout", Person.find_by!(x_id: "901").handle
    assert_equal 1, result[:skipped]
    assert_equal 1, result[:posts]
  end

  test "batches from another X account or unknown operations are refused or ignored" do
    error = assert_raises(X::Capture::Rejected) { capture!(web_response("HomeTimeline", web_timeline([])), viewer: "12345") }
    assert_match "different X account", error.message

    result = capture!({ "operation" => "DMInbox", "body" => "{}" })
    assert_equal 1, result[:ignored]
  end
end
