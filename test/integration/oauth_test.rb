require "test_helper"

# Linking clients with OAuth 2.1: an AI assistant that only knows the MCP URL, and the browser extension.
class OauthTest < ActionDispatch::IntegrationTest
  CLAUDE_REDIRECT = "https://claude.ai/api/mcp/auth_callback".freeze
  EXTENSION_REDIRECT = "https://#{Oauth::Client::EXTENSION_ID}.chromiumapp.org/oauth".freeze

  setup do
    @verifier = SecureRandom.urlsafe_base64(48)
    @challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false)
  end

  def register(redirect_uris: [ CLAUDE_REDIRECT ], **extra)
    post oauth_register_path, params: { client_name: "Claude", redirect_uris: redirect_uris, **extra }.to_json,
      headers: { "Content-Type" => "application/json" }
    response.parsed_body
  end

  def authorize_params(client_id, redirect_uri: CLAUDE_REDIRECT, **overrides)
    { client_id: client_id, redirect_uri: redirect_uri, response_type: "code", code_challenge: @challenge,
      code_challenge_method: "S256", state: "xyz", resource: "http://www.example.com/mcp" }.merge(overrides)
  end

  def approve(client_id, **overrides)
    post oauth_authorize_path, params: authorize_params(client_id, **overrides).merge(decision: "approve")
    query = Rack::Utils.parse_query(URI.parse(response.location).query)
    query
  end

  def exchange(client_id, code, redirect_uri: CLAUDE_REDIRECT, verifier: @verifier)
    post oauth_token_path, params: { grant_type: "authorization_code", client_id: client_id, code: code,
      redirect_uri: redirect_uri, code_verifier: verifier, resource: "http://www.example.com/mcp" }
    response.parsed_body
  end

  def mcp_ping(token)
    post mcp_path, params: { jsonrpc: "2.0", id: 1, method: "ping" }.to_json,
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
  end

  def link_claude
    client_id = register.fetch("client_id")
    tokens = exchange(client_id, approve(client_id).fetch("code"))
    [ client_id, tokens ]
  end

  test "an assistant with only the MCP URL discovers the authorization server" do
    sign_out
    mcp_ping(nil)
    assert_response :unauthorized
    assert_match %r{resource_metadata="http://www.example.com/.well-known/oauth-protected-resource/mcp"}, response.headers["WWW-Authenticate"]

    get "/.well-known/oauth-protected-resource/mcp"
    assert_equal "http://www.example.com/mcp", response.parsed_body["resource"]
    assert_equal [ "http://www.example.com" ], response.parsed_body["authorization_servers"]
    get "/.well-known/oauth-protected-resource/x/captures"
    assert_equal "http://www.example.com/x/captures", response.parsed_body["resource"]

    get "/.well-known/oauth-authorization-server"
    metadata = response.parsed_body
    assert_equal "http://www.example.com/oauth/register", metadata["registration_endpoint"]
    assert_equal %w[S256], metadata["code_challenge_methods_supported"]
  end

  test "a registered assistant links after the owner approves, and its token reaches only MCP" do
    client_id = register.fetch("client_id")
    get oauth_authorize_path, params: authorize_params(client_id)
    assert_response :success
    assert_includes response.body, "Connect Claude to Xtend?"
    assert_includes response.body, "This app named itself"
    assert_match "https://claude.ai", response.headers["Content-Security-Policy"][/form-action [^;]+/]

    query = approve(client_id)
    assert_equal %w[code iss state], query.keys.sort
    assert_equal "xyz", query["state"]
    tokens = exchange(client_id, query["code"])
    assert_equal "mcp", tokens["scope"]
    assert_match(/\Axtend_at_/, tokens["access_token"])

    sign_out
    mcp_ping(tokens["access_token"])
    assert_response :success
    post x_captures_path, params: { batch_key: "k", viewer_x_id: "999", responses: [] }.to_json,
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{tokens["access_token"]}" }
    assert_response :unauthorized
    assert Oauth::Grant.sole.last_used_at
  end

  test "a code works once, only with its verifier, redirect, and client" do
    client_id = register.fetch("client_id")
    code = approve(client_id).fetch("code")
    assert_equal "invalid_grant", exchange(client_id, code, verifier: SecureRandom.urlsafe_base64(48))["error"]
    assert_equal "invalid_grant", exchange(client_id, code, redirect_uri: "https://claude.ai/other")["error"]
    other = register.fetch("client_id")
    assert_equal "invalid_grant", exchange(other, code)["error"]
    assert exchange(client_id, code)["access_token"]
    assert_equal "invalid_grant", exchange(client_id, code)["error"]
  end

  test "refreshing rotates the pair, and a stolen refresh token replayed later ends the link" do
    client_id, tokens = link_claude
    post oauth_token_path, params: { grant_type: "refresh_token", client_id: client_id, refresh_token: tokens["refresh_token"] }
    renewed = response.parsed_body
    assert renewed["access_token"]
    assert_not_equal tokens["access_token"], renewed["access_token"]

    travel Oauth::Token::REUSE_GRACE + 1.second do
      post oauth_token_path, params: { grant_type: "refresh_token", client_id: client_id, refresh_token: tokens["refresh_token"] }
      assert_equal "invalid_grant", response.parsed_body["error"]
    end
    assert Oauth::Grant.sole.revoked?
    sign_out
    mcp_ping(renewed["access_token"])
    assert_response :unauthorized
  end

  test "the owner can deny, and the client can revoke" do
    client_id = register.fetch("client_id")
    post oauth_authorize_path, params: authorize_params(client_id).merge(decision: "deny")
    assert_equal "access_denied", Rack::Utils.parse_query(URI.parse(response.location).query)["error"]
    assert_equal 0, Oauth::Grant.count

    client_id, tokens = link_claude
    post oauth_revoke_path, params: { client_id: client_id, token: tokens["access_token"] }
    assert_response :success
    assert Oauth::Grant.sole.revoked?
  end

  test "connected apps lists the link, and disconnecting ends it" do
    _, tokens = link_claude
    get ai_connector_path
    assert_select "button[aria-label=?]", "Disconnect Claude"
    delete oauth_grant_path(Oauth::Grant.sole)
    assert Oauth::Grant.sole.revoked?
    sign_out
    mcp_ping(tokens["access_token"])
    assert_response :unauthorized
  end

  test "the extension links with its per-install redirect and can only send captures" do
    client_id = "xtend-capture"
    assert_not Oauth::Client.exists?(client_id: client_id), "a fresh database has no first-party clients yet"
    params = { redirect_uri: EXTENSION_REDIRECT, scope: "capture", resource: "http://www.example.com/x/captures" }
    get oauth_authorize_path, params: authorize_params(client_id, **params)
    assert_includes response.body, "Connect Xtend Capture extension to Xtend?"
    assert_not_includes response.body, "This app named itself"
    code = approve(client_id, **params).fetch("code")
    post oauth_token_path, params: { grant_type: "authorization_code", client_id: client_id, code: code,
      redirect_uri: EXTENSION_REDIRECT, code_verifier: @verifier, resource: "http://www.example.com/x/captures" }
    access = response.parsed_body.fetch("access_token")

    sign_out
    post x_captures_path, params: { batch_key: SecureRandom.uuid, viewer_x_id: "999", responses: [] }.to_json,
      headers: { "Content-Type" => "application/json", "Origin" => "chrome-extension://abcdefghijklmnop", "Authorization" => "Bearer #{access}" }
    assert_response :success
    mcp_ping(access)
    assert_response :unauthorized
  end

  test "another extension can't link as the Xtend extension" do
    get oauth_authorize_path, params: authorize_params("xtend-capture", redirect_uri: "https://abcdefghijklmnopabcdefghijklmnop.chromiumapp.org/oauth",
      scope: "capture", resource: "http://www.example.com/x/captures")
    assert_response :bad_request
  end

  test "revoking a user disconnects what they linked, and refreshing ends the old access token" do
    client_id, tokens = link_claude
    post oauth_token_path, params: { grant_type: "refresh_token", client_id: client_id, refresh_token: tokens["refresh_token"] }
    renewed = response.parsed_body.fetch("access_token")
    sign_out
    mcp_ping(tokens["access_token"])
    assert_response :unauthorized
    mcp_ping(renewed)
    assert_response :success

    @user.destroy!
    mcp_ping(renewed)
    assert_response :unauthorized
  end

  test "requests that can't be trusted stop before approval" do
    client_id = register.fetch("client_id")
    get oauth_authorize_path, params: authorize_params(client_id, redirect_uri: "https://evil.example/callback")
    assert_response :bad_request
    get oauth_authorize_path, params: authorize_params("unknown")
    assert_response :bad_request

    get oauth_authorize_path, params: authorize_params(client_id, code_challenge_method: "plain")
    assert_equal "invalid_request", Rack::Utils.parse_query(URI.parse(response.location).query)["error"]
    get oauth_authorize_path, params: authorize_params(client_id, scope: "capture")
    assert_equal "invalid_scope", Rack::Utils.parse_query(URI.parse(response.location).query)["error"]
    get oauth_authorize_path, params: authorize_params(client_id, resource: "http://www.example.com/x/captures")
    assert_equal "invalid_target", Rack::Utils.parse_query(URI.parse(response.location).query)["error"]

    sign_out
    get oauth_authorize_path, params: authorize_params(client_id)
    assert_redirected_to new_session_path
  end

  test "registration accepts only public clients with safe redirects, and unapproved ones are pruned" do
    assert_equal "invalid_redirect_uri", register(redirect_uris: [ "http://claude.ai/callback" ])["error"]
    assert_equal "invalid_redirect_uri", register(redirect_uris: [])["error"]
    assert_equal "invalid_client_metadata", register(token_endpoint_auth_method: "client_secret_basic")["error"]
    assert register(redirect_uris: [ "http://localhost:6274/callback" ])["client_id"]

    travel Oauth::Client::UNUSED_REGISTRATION_LIFETIME + 1.hour do
      link_claude
      Oauth::Client.prune!
    end
    assert_equal [ "Claude" ], Oauth::Client.dynamic.pluck(:name)
  end
end
