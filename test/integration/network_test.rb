require "test_helper"
require_relative "../test_helpers/web_capture_helper"

class NetworkTest < ActionDispatch::IntegrationTest
  include WebCaptureHelper

  test "the network shows an empty state, then people linked by captured interactions" do
    get network_path
    assert_response :success
    assert_includes response.body, "No interactions collected yet."

    alice = Person.resolve_profile!(profile(x_id: "201", handle: "alice"))
    bob = Person.resolve_profile!(profile(x_id: "202", handle: "bob"))
    Person.resolve_profile!(profile(x_id: "203", handle: "quiet"))
    capture!(web_response("TweetDetail", { "data" => [
      web_tweet("2100", web_user("201", "alice")),
      web_tweet("2101", web_user("202", "bob"), reply_to: { post: "2100", user: "201" }),
      web_tweet("2102", web_user("204", "outsider"), reply_to: { post: "2100", user: "201" }),
      web_tweet("2103", web_user("202", "bob"), text: "cc", mentions: [ web_user("204", "outsider") ])
    ] }))
    capture!(web_response("TweetDetail", { "data" => [ web_tweet("2104", web_user("201", "alice"), text: "hey", mentions: [ web_user("204", "outsider") ]) ] }))

    get network_path(format: :json)
    graph = response.parsed_body
    assert_equal %w[201 202], graph["nodes"].map { |node| node["id"] }.sort
    assert_equal [ [ "202", "201", { "reply" => 1 } ] ], graph["links"].map { |link| link.values_at("source", "target", "kinds") }
    assert_equal 1, graph["isolated"]

    get network_path(format: :json, outside: "1")
    assert_includes response.parsed_body["nodes"].map { |node| node["id"] }, "204"

    get network_path(format: :json, kinds: [ "like" ])
    assert_empty response.parsed_body["links"]

    get network_path
    assert_select "[data-controller=network]"
    assert_select "#most-connected"
    assert_equal [ alice.id, bob.id ].sort, Person.where(x_id: %w[201 202]).pluck(:id).sort
  end

  test "the timeline lists network posts with counts, filters, and sorts without strangers by default" do
    alice = Person.resolve_profile!(profile(x_id: "301", handle: "alice"))
    capture!(web_response("HomeTimeline", web_timeline([
      web_tweet("3101", web_user("301", "alice"), text: "Small post", likes: 5),
      web_tweet("3102", web_user("301", "alice"), text: "Big post", likes: 900, media: %w[photo]),
      web_tweet("3103", web_user("399", "stranger"), text: "Stranger post", likes: 9000),
      web_tweet("3104", web_user("301", "alice"), text: "A reply", reply_to: { post: "3103", user: "399" })
    ])))

    get timeline_path
    assert_response :success
    assert_select "#post_3101"
    assert_select "#post_3103", count: 0
    assert_select "#post_3104", count: 0
    get timeline_path(sort: "likes")
    assert_operator response.body.index("Big post"), :<, response.body.index("Small post")
    get timeline_path(who: "seen")
    assert_select "#post_3103"
    get timeline_path(kind: "replies")
    assert_select "#post_3104", text: /Replying to @stranger/
    get timeline_path(media: "1")
    assert_select "ol > li", 1
    get timeline_path(person_id: alice.id, kind: "all")
    assert_select "ol > li", 3
  end
end
