require "test_helper"

class FollowListsAndInboxTest < ActionDispatch::IntegrationTest
  test "follow review shows progress, inline posts, tag suggestions, and the Grok relevance prompt" do
    a = Person.resolve_profile!(profile(x_id: "51", handle: "alpha"))
    b = Person.resolve_profile!(profile(x_id: "52", handle: "bravo"))
    snapshot("following", [ a, b ], observed_at: 2.days.ago)
    snapshot("following", [ a ], observed_at: 1.hour.ago)
    Follow::Review.record!(b, "reported_unfollow")
    Grok::Proposal.create!(person: a, kind: "tags", status: "pending", via: "paste", payload: { "tags" => [ "off-topic" ], "reason" => "Posts only about sports" })

    get follow_reviews_path(mutuals: "1", reason: "strangers")
    assert_response :success
    assert_includes response.body, "Grok suggests"
    assert_select "button[aria-label=?]", "Accept Grok's tags for A Builder"
    assert_includes response.body, "Ask Grok which of these 1 fit your interests"
    assert_includes response.body, "2 → 1 since"
    assert_select "[data-controller=chart]", 2

    patch grok_proposal_path(Grok::Proposal.last), params: { decision: "accept" }, headers: { "HTTP_REFERER" => follow_reviews_path(mutuals: "1") }
    assert_redirected_to follow_reviews_path(mutuals: "1")
    assert_equal [ "off-topic" ], a.reload.tags.map(&:name)
  end

  test "followers opens on changes, and X data shows each list with a link to scroll it on x.com" do
    get follower_history_path
    assert_response :success
    assert_includes response.body, "No changes between complete lists yet."

    get x_sources_path
    assert_response :success
    assert_includes response.body, "No complete list yet"
  end

  test "replies to you can be set aside" do
    event = ingest(direction: "incoming", x_id: "6001", target_x_id: "6000")
    get inbox_path
    assert_response :success
    assert_select "a[aria-label='Reply on X'][href$='/status/6001']"
    assert_select "button[aria-label^='Set aside the reply']"

    post reply_event_dismissal_path(event)
    assert_redirected_to inbox_path
    follow_redirect!
    assert_includes response.body, "Nothing waiting on you."
  end

  test "pages can ask when the extension last delivered something, and trials render" do
    get x_capture_status_path
    assert_equal({ "captured_at" => nil, "summary" => nil }, response.parsed_body)
    Current.workspace.update!(captured_at: Time.current, last_capture: { "posts" => 2 })
    get x_capture_status_path
    assert_equal "2 posts", response.parsed_body["summary"]

    get follow_trials_path
    assert_response :success
    assert_includes response.body, "Needs a first complete following list."
    assert_select "[data-controller=live]"
  end
end
