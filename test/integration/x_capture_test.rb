require "test_helper"
require_relative "../test_helpers/web_capture_helper"

class XCaptureEndpointTest < ActionDispatch::IntegrationTest
  include WebCaptureHelper

  setup { @token = paste_token("capture") }

  def send_batch(token: @token, origin: "chrome-extension://abcdefghijklmnop", viewer: Current.workspace.owner_x_id)
    body = { batch_key: SecureRandom.uuid, viewer_x_id: viewer,
      responses: [ web_response("HomeTimeline", web_timeline([ web_tweet("1001", web_user("101", "builder")) ])) ] }
    post x_captures_path, params: body.to_json, headers: { "Content-Type" => "application/json", "Origin" => origin,
      "Authorization" => ("Bearer #{token}" if token) }.compact
  end

  test "the extension's token sends a batch without a browser session" do
    sign_out
    send_batch
    assert_response :success
    assert_equal [ 1, 1, 0 ], response.parsed_body.values_at("posts", "accounts", "people_added")
    assert Current.workspace.oauth_grants.sole.last_used_at
  end

  test "the status page shows whether the extension is reaching Xtend and what it delivered" do
    get x_capture_status_path
    assert_includes response.body, "Not connected"
    send_batch
    get x_capture_status_path
    assert_response :success
    assert_includes response.body, "Working"
    assert_includes response.body, "1 feed post"
    assert_equal 1, X::CaptureActivity.new.batch_count(1.hour.ago)
  end

  test "an empty batch tests the token and X account without saving anything" do
    post x_captures_path, params: { batch_key: SecureRandom.uuid, viewer_x_id: Current.workspace.owner_x_id, responses: [] }.to_json,
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@token}" }
    assert_response :success
    assert_equal 0, X::SyncRun.count
  end

  test "missing, revoked, or MCP tokens are refused" do
    send_batch(token: nil)
    assert_response :unauthorized
    send_batch(token: paste_token("mcp"))
    assert_response :unauthorized
    Current.workspace.oauth_grants.where(scope: "capture").each(&:revoke!)
    send_batch
    assert_response :unauthorized
    assert_equal 0, Person.count
  end

  test "web pages cannot post captures and another X account is refused" do
    send_batch(origin: "https://x.com")
    assert_response :forbidden
    send_batch(viewer: "12345")
    assert_response :unprocessable_entity
    assert_match "different X account", response.parsed_body["error"]
  end

  test "the X data page issues a pasted token once and lists it under connected apps" do
    post oauth_grants_path, params: { scope: "capture" }
    assert_response :success
    assert_select "#capture-token"
    get x_sources_path
    assert_select "#capture button[aria-label=?]", "Disconnect Pasted token", count: 2
  end
end
