require "test_helper"

class McpTest < ActionDispatch::IntegrationTest
  setup do
    @token = Workspace.current.issue_mcp_token!
    @person = Person.resolve_profile!(profile(x_id: "555", handle: "builder", name: "A Builder"))
    @person.update!(notes: "Private note")
  end

  def rpc(method, params = {}, id: 1, token: @token, headers: {})
    body = { jsonrpc: "2.0", method: method, params: params }
    body[:id] = id if id
    post mcp_path, params: body.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
      "Authorization" => ("Bearer #{token}" if token) }.compact.merge(headers)
    response.body.present? ? JSON.parse(response.body) : nil
  end

  def tool(name, arguments = {})
    result = rpc("tools/call", { name: name, arguments: arguments })
    assert_response :success
    result.fetch("result")
  end

  test "the endpoint requires the current token and rejects foreign browser origins" do
    rpc("ping", token: nil)
    assert_response :unauthorized
    rpc("ping", token: "crm_wrong")
    assert_response :unauthorized
    rpc("ping", headers: { "Origin" => "https://evil.example" })
    assert_response :forbidden
    assert_equal({}, rpc("ping")["result"])
    Workspace.current.revoke_mcp_token!
    rpc("ping")
    assert_response :unauthorized
  end

  test "initialize, notifications, unknown methods, and unsupported HTTP verbs follow the protocol" do
    result = rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" } })["result"]
    assert_equal "2025-06-18", result["protocolVersion"]
    assert result.dig("capabilities", "tools")
    assert_nil rpc("notifications/initialized", id: nil)
    assert_response :accepted
    assert_equal(-32601, rpc("nope")["error"]["code"])
    post mcp_path, params: "{bad", headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@token}" }
    assert_response :bad_request
    get mcp_path, headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :method_not_allowed
  end

  test "tools are listed with schemas and none can act on X" do
    names = rpc("tools/list")["result"]["tools"].map { |definition| definition["name"] }
    assert_equal Mcp::Tools.names, names
    assert names.none? { |name| name.match?(/post_reply|follow|unfollow|send|message|delete/) }
  end

  test "read tools respect sharing choices and limits" do
    context = tool("get_person_context", { "handle" => "builder" })["structuredContent"]
    assert_equal "builder", context["handle"]
    assert_not context.key?("notes")
    DirectMessage.create!(x_id: "d1", conversation_x_id: "c1", partner_x_id: "555", direction: "incoming", occurred_at: 1.day.ago, source: "archive")
    history = tool("get_interaction_history", { "person_id" => @person.id })["structuredContent"]
    assert history["events"].none? { |event| event["kind"] == "dm" }
    assert_not history["coverage"].key?("DMs")

    Workspace.current.update!(mcp_share_notes: true, mcp_share_dms: true)
    assert_equal "Private note", tool("get_person_context", { "person_id" => @person.id })["structuredContent"]["notes"]
    assert tool("get_interaction_history", { "person_id" => @person.id })["structuredContent"]["events"].any? { |event| event["kind"] == "dm" }

    other = Person.resolve_profile!(profile(x_id: "556", handle: "other", name: "Other"))
    snapshot("following", [@person, other])
    assert_empty tool("list_people", { "filter" => "mutual" })["structuredContent"]["people"], "an incomplete graph cannot establish mutuals"
    snapshot("followers", [@person])
    assert_equal ["builder"], tool("list_people", { "filter" => "mutual" })["structuredContent"]["people"].map { |person| person["handle"] }
    assert_equal %w[builder other], tool("list_people", { "filter" => "you_follow" })["structuredContent"]["people"].map { |person| person["handle"] }
    assert_equal "Mutual", tool("get_person_context", { "person_id" => @person.id })["structuredContent"]["follow_state"]
    listed = tool("list_people", { "limit" => 1 })["structuredContent"]
    assert_equal 1, listed["people"].size
    assert tool("list_people", { "limit" => 500 })["isError"]
    assert tool("get_person_context", { "handle" => "nobody" })["isError"]
    assert_equal 20, tool("get_session_state")["structuredContent"]["target"]
  end

  test "proposing candidates stages them for Today without X reads" do
    result = tool("propose_candidate_posts", { "posts" => [{ "url" => "https://x.com/builder/status/8101", "text" => "How do you test Rails jobs?",
      "published_at" => 1.hour.ago.iso8601, "match_reason" => "Rails testing question" }] })
    assert_not result["isError"]
    assert_equal "created", result["structuredContent"]["posts"].first["status"]
    assert_includes tool("list_known_posts")["structuredContent"]["post_ids"], "8101"
    assert_equal 1, tool("get_session_state")["structuredContent"]["queue"]["unverified_from_grok"]
    assert_equal 0, X::Read.count

    get root_path
    assert_includes response.body, "Unverified · from Grok"
    assert_includes response.body, "Verify on X"
  end

  test "settings shows the token once, paste intake works, and proposals are reviewed on the person page" do
    get settings_path
    assert_includes response.body, "Grok Bot connector (MCP)"
    assert_not_includes response.body, @token
    post mcp_token_path
    assert_response :success
    new_token = response.body[/crm_[A-Za-z0-9_-]{20,}/]
    assert new_token
    assert Workspace.current.mcp_token_matches?(new_token)
    assert_not Workspace.current.mcp_token_matches?(@token)

    paste = "Results:\n```json\n" + { format: "twitter-crm-grok-v1", recaps: [{ handle: "builder", summary: "Ships Rails tools." }] }.to_json + "\n```"
    post grok_intakes_path, params: { grok_output: paste }
    assert_redirected_to settings_path(anchor: "discovery")
    assert_match "1 staged", flash[:notice]
    get person_path(@person)
    assert_includes response.body, "Proposed recap"
    patch grok_proposal_path(Grok::Proposal.last), params: { decision: "accept" }
    follow_redirect!
    assert_includes response.body, "Ships Rails tools."
  end
end
