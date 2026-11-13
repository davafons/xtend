require "test_helper"

class McpTest < ActionDispatch::IntegrationTest
  setup do
    @token = paste_token("mcp")
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
    rpc("ping", token: "xtend_wrong")
    assert_response :unauthorized
    rpc("ping", headers: { "Origin" => "https://evil.example" })
    assert_response :forbidden
    assert_equal({}, rpc("ping")["result"])
    Current.workspace.oauth_grants.each(&:revoke!)
    rpc("ping")
    assert_response :unauthorized
  end

  test "a token reads only its own workspace" do
    other = Workspace.create!(name: "Other", owner_x_id: "888")
    other_token = paste_token("mcp", workspace: other)
    Current.set(workspace: other) { Person.resolve_profile!(profile(x_id: "777", handle: "theirs", name: "Theirs")) }
    rpc("tools/call", { name: "list_people", arguments: {} }, token: other_token)
    assert_equal [ "theirs" ], JSON.parse(response.body).dig("result", "structuredContent", "people").map { |person| person["handle"] }
    assert tool("get_person_context", { "handle" => "theirs" })["isError"]
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
    instructions = rpc("initialize", { protocolVersion: "2025-06-18" })["result"]["instructions"]
    assert_no_match(/grok/i, instructions + Mcp::Tools.definitions.to_json.gsub(/AI::\w+/, ""))
  end

  test "read tools respect sharing choices and limits" do
    context = tool("get_person_context", { "handle" => "builder" })["structuredContent"]
    assert_equal "builder", context["handle"]
    assert_not context.key?("notes")
    DirectMessage.create!(x_id: "d1", conversation_x_id: "c1", partner_x_id: "555", direction: "incoming", occurred_at: 1.day.ago, source: "archive")
    history = tool("get_interaction_history", { "person_id" => @person.id })["structuredContent"]
    assert history["events"].none? { |event| event["kind"] == "dm" }
    assert_not history["coverage"].key?("DMs")

    Current.workspace.update!(mcp_share_notes: true, mcp_share_dms: true)
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

  test "proposing candidates stages them without X reads" do
    result = tool("propose_candidate_posts", { "posts" => [{ "url" => "https://x.com/builder/status/8101", "text" => "How do you test Rails jobs?",
      "published_at" => 1.hour.ago.iso8601, "match_reason" => "Rails testing question" }] })
    assert_not result["isError"]
    assert_equal "created", result["structuredContent"]["posts"].first["status"]
    assert_includes tool("list_known_posts")["structuredContent"]["post_ids"], "8101"
    assert_equal 1, tool("get_session_state")["structuredContent"]["queue"]["unverified_from_ai"]
    assert_equal 0, X::Read.count
  end

  test "settings shows the token once, paste intake works, and proposals are reviewed on the person page" do
    get ai_connector_path
    assert_includes response.body, "Assistant connector (MCP)"
    assert_includes response.body, "claude mcp add --transport http xtend"
    assert_select "a[aria-current=page]", text: "AI"
    assert_not_includes response.body, @token
    # The token page renders instead of redirecting, which Turbo Drive ignores, so the form must skip Turbo.
    assert_select "form[action=?] button[data-turbo=false]", oauth_grants_path
    post oauth_grants_path, params: { scope: "mcp" }
    assert_response :success
    new_token = response.body[/xtend_[A-Za-z0-9_-]{20,}/]
    assert new_token
    assert_includes response.body, "Authorization: Bearer #{new_token}"
    assert_equal Current.workspace, Oauth::Grant.authenticate(new_token, scope: "mcp").workspace
    assert Oauth::Grant.authenticate(@token, scope: "mcp"), "each pasted token is its own connection"

    paste = "Results:\n```json\n" + { format: "xtend-grok-v1", recaps: [{ handle: "builder", summary: "Ships Rails tools." }] }.to_json + "\n```"
    post ai_intakes_path, params: { ai_output: paste }
    assert_redirected_to ai_connector_path
    assert_match "1 staged", flash[:notice]
    get person_path(@person)
    assert_includes response.body, "Proposed recap"
    patch ai_proposal_path(AI::Proposal.last), params: { decision: "accept" }
    follow_redirect!
    assert_includes response.body, "Ships Rails tools."
  end

  test "an assistant can read tags, list untagged people, and propose tags for review" do
    @person.add_tags!("tokyo")
    Person.resolve_profile!(profile(x_id: "556", handle: "other", name: "Other"))
    assert_equal [{ "name" => "tokyo", "people" => 1 }], tool("get_owner_profile")["structuredContent"]["tags"]
    assert_equal ["other"], tool("list_people", { "filter" => "untagged" })["structuredContent"]["people"].map { |person| person["handle"] }
    assert_equal [["builder", ["tokyo"]]], tool("list_people", { "tag" => "tokyo" })["structuredContent"]["people"].map { |person| [person["handle"], person["tags"]] }
    result = tool("propose_tags", { "assignments" => [{ "handle" => "other", "tags" => ["designer"], "reason" => "Bio" }] })
    assert_equal "staged", result["structuredContent"]["tags"].first["status"]
    assert_empty Tag.where(name: "designer")
    assert tool("propose_tags", { "assignments" => [] })["isError"]
  end

  test "an assistant sees what still awaits review, and nothing applies until the owner accepts" do
    tool("propose_tags", { "assignments" => [{ "handle" => "builder", "tags" => ["rails"], "reason" => "Bio" }] })
    tool("propose_recap", { "handle" => "builder", "summary" => "Ships Rails tools." })
    tool("propose_candidate_posts", { "posts" => [{ "url" => "https://x.com/builder/status/8101", "text" => "How do you test Rails jobs?",
      "published_at" => 1.hour.ago.iso8601, "match_reason" => "Rails testing question" }] })
    pending = tool("list_pending_proposals")["structuredContent"]
    assert_equal [ [ "recap", "builder" ], [ "tags", "builder" ] ], pending["proposals"].map { |item| [ item["kind"], item.dig("person", "handle") ] }.sort
    assert_equal [ "rails" ], pending["proposals"].find { |item| item["kind"] == "tags" }.dig("proposed", "tags")
    assert_equal [ "https://x.com/i/status/8101" ], pending["unverified_posts"].map { |post| post["url"] }
    tags_only = tool("list_pending_proposals", { "kind" => "tags" })["structuredContent"]
    assert_equal [ "tags" ], tags_only["proposals"].map { |item| item["kind"] }
    assert_not tags_only.key?("unverified_posts")
    assert_equal 1, tool("list_pending_proposals", { "kind" => "posts" })["structuredContent"]["unverified_posts_total"]
    assert tool("list_pending_proposals", { "kind" => "follows" })["isError"]
    assert_empty @person.reload.tags

    AI::Proposal.pending.find_by!(kind: "tags").accept!
    assert_equal [ "recap" ], tool("list_pending_proposals")["structuredContent"]["proposals"].map { |item| item["kind"] }
  end

  test "an assistant saves post ideas with variations and adds more without posting anything" do
    result = tool("save_post_idea", { "texts" => [ "SQLite is enough for most side projects.", "Your side project doesn't need Postgres." ], "topic" => "Rails", "variation_note" => "contrarian hook" })
    saved = result.fetch("structuredContent").fetch("draft")
    draft = Draft.find(saved["id"])
    assert_equal [ "ai", "idea", "SQLite is enough for most side projects." ], [ draft.source, draft.status, draft.body ]
    assert_equal [ "contrarian hook" ], draft.alternatives.map(&:note)
    assert_equal "ai", saved["written_by"]

    tool("add_post_variations", { "draft_id" => draft.id, "texts" => [ "Hot take: SQLite.", "Thread version\n---\nPart two" ] })
    assert_equal 3, draft.alternatives.count
    listed = tool("list_post_drafts").fetch("structuredContent").fetch("drafts")
    assert_equal 3, listed.find { |item| item["id"] == draft.id }["alternatives"].size

    assert tool("save_post_idea", { "texts" => [] })["isError"]
    assert tool("add_post_variations", { "draft_id" => 0, "texts" => [ "x" ] })["isError"]
    assert tool("save_post_idea", { "texts" => [ "x" ], "inspiration_url" => "javascript:alert(1)" })["isError"]
    assert_equal 0, X::Read.count
  end

  test "an assistant reads how the owner's posts did, settled counts only" do
    run = X::SyncRun.create!(dataset: "posts", mode: "capture", owner_x_id: "999", request_key: SecureRandom.uuid, page_limit: 1, upper_bound: Time.current)
    X::SourcePost.create!(x_id: "6001", author_x_id: "999", body: "Shipped it", published_at: 5.days.ago, x_sync_run: run, view_count: 900, like_count: 20, media_kinds: "photo", metrics_observed_at: 1.day.ago)
    X::SourcePost.create!(x_id: "6002", author_x_id: "999", body: "Just now", published_at: 2.hours.ago, x_sync_run: run, view_count: 50, metrics_observed_at: 1.hour.ago)
    X::SourcePost.create!(x_id: "6003", author_x_id: "999", body: "Never seen", published_at: 3.days.ago, x_sync_run: run)
    result = tool("get_post_performance").fetch("structuredContent")
    assert_equal [ 1, 1, 1 ], result.values_at("compared", "too_fresh", "without_counts")
    assert_equal [ "photo" ], result["by_format"].map { _1["format"] }
    assert_equal [ "https://x.com/i/status/6001" ], result["top_posts"].map { _1["url"] }
    assert tool("get_post_performance", { "days" => 0 })["isError"]
  end

  test "an assistant reads network posts with counts and the network around a person" do
    alice = Person.resolve_profile!(profile(x_id: "401", handle: "alice"))
    Person.resolve_profile!(profile(x_id: "402", handle: "bob"))
    run = X::SyncRun.create!(dataset: "posts", owner_x_id: Current.workspace.owner_x_id, request_key: SecureRandom.uuid, mode: "capture", status: "completed", page_limit: 1, upper_bound: Time.current)
    X::SourcePost.capture!({ "id" => "4100", "author_id" => "401", "text" => "Ship small", "created_at" => 1.hour.ago.iso8601, "referenced_posts" => [] },
      run: run, details: { like_count: 120, view_count: 5000, has_link: false })
    X::SourcePost.capture!({ "id" => "4101", "author_id" => "402", "text" => "@alice agreed", "created_at" => 30.minutes.ago.iso8601, "in_reply_to_user_id" => "401",
      "referenced_posts" => [ { "id" => "4100", "type" => "replied_to" } ] }, run: run)

    posts = tool("list_network_posts", { "sort" => "likes" }).fetch("structuredContent").fetch("posts")
    assert_equal [ "alice", "Ship small", 120 ], posts.first.values_at("author", "text").push(posts.first.dig("counts", "like_count"))
    network = tool("get_network", { "handle" => "alice" }).fetch("structuredContent")
    assert_equal [ [ "bob", { "reply" => 1 } ] ], network["interacts_with"].map { |item| item.values_at("handle", "interactions") }
    overview = tool("get_network").fetch("structuredContent")
    assert_equal [ { "from" => "bob", "to" => "alice", "interactions" => { "reply" => 1 } } ], overview["busiest_pairs"]
    assert_equal alice.id, overview["most_connected"].first["person_id"]
  end
end
