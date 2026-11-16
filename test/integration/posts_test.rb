require "test_helper"
require_relative "../test_helpers/web_capture_helper"

class PostsTest < ActionDispatch::IntegrationTest
  include WebCaptureHelper

  test "a post's page shows the saved conversation around it, its media, and quotes, and timeline posts link to it" do
    Person.resolve_profile!(profile(x_id: "201", handle: "alice"))
    Person.resolve_profile!(profile(x_id: "202", handle: "bob"))
    video = { "type" => "video", "media_url_https" => "https://pbs.twimg.com/amplify_video_thumb/1/img/V.jpg",
      "video_info" => { "variants" => [ { "content_type" => "video/mp4", "bitrate" => 832_000, "url" => "https://video.twimg.com/amplify_video/1/vid/V.mp4" } ] } }
    demo = web_tweet("3001", web_user("201", "alice"), text: "Here's the demo", reply_to: { post: "3000", user: "201", conversation: "2999" }, media: [ video ])
    capture!(web_response("TweetDetail", { "data" => [
      web_tweet("3000", web_user("201", "alice"), text: "Root post", reply_to: { post: "2999", user: "203" }),
      demo,
      web_tweet("3002", web_user("202", "bob"), text: "Looks great", reply_to: { post: "3001", user: "201", conversation: "2999" }),
      web_tweet("3003", web_user("202", "bob"), text: "Worth watching", quoted: demo)
    ] }))

    get post_path("3001")
    assert_response :success
    assert_select "video[src='https://video.twimg.com/amplify_video/1/vid/V.mp4'][controls]"
    assert_includes response.body, "Root post"
    assert_includes response.body, "Replies to a post Xtend hasn't saved."
    assert_select "ol[aria-label=Replies] li", 1
    assert_includes response.body, "Looks great"
    assert_includes response.body, "Worth watching"
    assert_select "article [data-controller~=post-link]", false, "the post the page is about doesn't link to itself"
    assert_select "[data-post-link-url-value='#{post_path('3002')}']"

    get timeline_path(kind: "all", who: "seen")
    assert_select "[data-post-link-url-value='#{post_path('3001')}']"
    assert_select "a[href='#{post_path('3001')}']", minimum: 1

    get post_path("404404")
    assert_response :not_found
  end
end
