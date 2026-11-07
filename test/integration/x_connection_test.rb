require "test_helper"
require "minitest/mock"
require "tmpdir"
require "net/http"

class XConnectionTest < ActionDispatch::IntegrationTest
  class MockHTTP
    attr_reader :requests
    def initialize(responses)
      @responses = responses
      @requests = []
    end
    def request(request)
      @requests << request
      item = @responses.shift || raise("Unexpected HTTP request")
      item.respond_to?(:call) ? item.call(request) : item
    end
  end

  def tokens(**overrides)
    {"access_token" => "test-access", "refresh_token" => "test-refresh", "token_type" => "bearer", "expires_in" => 7200, "scope" => X::Config::SCOPES.join(" ")}.merge(overrides.stringify_keys)
  end

  def response_json(data, code: 200)
    klass = Net::HTTPResponse::CODE_TO_OBJ.fetch(code.to_s)
    response = klass.new("1.1", code.to_s, "Test response")
    response.body = JSON.generate(data)
    response.instance_variable_set(:@read, true)
    response
  end

  def with_config(responses = [], client_secret: nil)
    https!
    host! "www.example.com"
    http = MockHTTP.new(responses)
    Dir.mktmpdir("crm-test-key") do |directory|
      X::TokenVault.stub(:key_path, Pathname.new(directory).join("x-token.key")) do
        X::Config.stub(:client_id, "test-client") do
          X::Config.stub(:client_secret, client_secret) do
            X::Config.stub(:redirect_uri, "https://www.example.com/x/connection/callback") do
              Net::HTTP.stub(:start, ->(*args, **options, &block) { block.call(http) }) { yield http }
            end
          end
        end
      end
    end
  end

  def start_connection
    post x_connection_path
    assert_response :redirect
    uri = URI.parse(response.location)
    assert_equal "x.com", uri.host
    URI.decode_www_form(uri.query).to_h
  end

  test "read-only PKCE flow connects a single owner and encrypts tokens" do
    with_config([response_json(tokens), response_json({data: {id: "999", username: "owner"}})]) do |http|
      query = start_connection
      assert_equal X::Config::SCOPES.sort, query.fetch("scope").split.sort
      assert_equal "S256", query.fetch("code_challenge_method")
      assert_not_includes query, "code_verifier"
      get callback_x_connection_path, params: {state: query.fetch("state"), code: "test-code"}
      assert_redirected_to settings_url
      connection = X::Connection.current
      assert_equal "999", connection.x_user_id
      assert_equal "owner", connection.username
      assert_not_includes connection.token_ciphertext, "test-access"
      assert_not_includes connection.token_ciphertext, "test-refresh"
      assert_equal 0o600, File.stat(X::TokenVault.key_path).mode & 0o777
      assert_equal "999", Current.workspace.owner_x_id
      assert_equal ["/2/oauth2/token", "/2/users/me?user.fields=profile_image_url"], http.requests.map(&:path)
      form = URI.decode_www_form(http.requests.first.body).to_h
      assert_equal query.fetch("code_challenge"), Base64.urlsafe_encode64(Digest::SHA256.digest(form.fetch("code_verifier")), padding: false)
      assert_equal "test-client", form.fetch("client_id")
      get context_export_path
      assert_not_includes response.body, "test-access"
      assert_not_includes response.body, "token_ciphertext"
    end
  end

  test "wrong state and reused callback never exchange tokens" do
    with_config do |http|
      query = start_connection
      get callback_x_connection_path, params: {state: "wrong", code: "test-code"}
      assert_redirected_to settings_path
      get callback_x_connection_path, params: {state: query.fetch("state"), code: "test-code"}
      assert_redirected_to settings_path
      assert_empty http.requests
      assert_nil X::Connection.current
    end
  end

  test "provider denial makes no API requests" do
    with_config do |http|
      query = start_connection
      get callback_x_connection_path, params: {state: query.fetch("state"), error: "access_denied"}
      assert_redirected_to settings_path
      assert_empty http.requests
      assert_nil X::Connection.current
    end
  end

  test "a different X account cannot replace this workspace owner" do
    with_config([response_json(tokens), response_json({data: {id: "888", username: "different"}})]) do
      query = start_connection
      get callback_x_connection_path, params: {state: query.fetch("state"), code: "test-code"}
      assert_redirected_to settings_path
      assert_nil X::Connection.current
      assert_equal "999", Current.workspace.owner_x_id
    end
  end

  test "extra write scope is rejected" do
    with_config([response_json(tokens(scope: X::Config::SCOPES.join(" ") + " tweet.write")), response_json({data: {id: "999", username: "owner"}})]) do
      query = start_connection
      get callback_x_connection_path, params: {state: query.fetch("state"), code: "test-code"}
      assert_nil X::Connection.current
    end
  end

  test "refresh rotation persists even if the following identity read fails" do
    with_config([response_json(tokens(access_token: "rotated-access", refresh_token: "rotated-refresh")), response_json({}, code: 503)]) do |http|
      connection = X::Connection.connect!(tokens, {"id" => "999", "username" => "owner"})
      connection.update!(expires_at: 1.minute.ago)
      assert_raises(X::Client::Error) { connection.check_identity! }
      stored = JSON.parse(X::TokenVault.decrypt(connection.reload.token_ciphertext))
      assert_equal "rotated-refresh", stored.fetch("refresh_token")
      assert connection.expires_at > Time.current
      assert_equal ["/2/oauth2/token", "/2/users/me?user.fields=profile_image_url"], http.requests.map(&:path)
    end
  end

  test "checking a valid connection reads only identity and disconnect preserves people" do
    picture = "https://pbs.twimg.com/profile_images/1/me_normal.jpg"
    with_config([response_json({data: {id: "999", username: "renamed", profile_image_url: picture}})]) do |http|
      X::Connection.connect!(tokens, {"id" => "999", "username" => "owner"})
      person = Person.create!(handle: "builder", name: "Builder", notes: "Keep my note")
      patch x_connection_path
      assert_redirected_to settings_path
      assert_equal "renamed", X::Connection.current.username
      assert_equal "https://pbs.twimg.com/profile_images/1/me_bigger.jpg", X::Connection.current.avatar_image_url
      assert_equal ["/2/users/me?user.fields=profile_image_url"], http.requests.map(&:path)
      delete x_connection_path
      assert_nil X::Connection.current
      assert_equal "Keep my note", person.reload.notes
      assert_equal "999", Current.workspace.owner_x_id
      assert_equal 1, http.requests.size
    end
  end

  test "missing config refuses connection and demo cannot authorize X" do
    X::Config.stub(:client_id, nil) do
      post x_connection_path
      assert_redirected_to settings_path
    end
    original = Rails.configuration.x.demo
    Rails.configuration.x.demo = true
    with_config do |http|
      post x_connection_path
      assert_redirected_to settings_path
      assert_empty http.requests
      assert_nil X::Connection.current
    end
  ensure
    Rails.configuration.x.demo = original
  end

  test "sensitive callback fields and authorize redirects are filtered" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    result = filter.filter({"code" => "secret-code", "state" => "secret-state", "code_verifier" => "secret-verifier", "access_token" => "secret-token"})
    assert result.values.all? { |value| value == "[FILTERED]" }
    assert_includes Rails.application.config.filter_redirect, "x.com/i/oauth2/authorize"
  end
  test "callback configuration is explicit and rejects unsafe or wrong paths" do
    ["https://example.com/wrong", "https://example.com/x/connection/callback?extra=1", "http://example.com/x/connection/callback"].each do |uri|
      X::Config.stub(:redirect_uri, uri) { assert_not X::Config.valid_redirect? }
    end
    X::Config.stub(:redirect_uri, "http://127.0.0.1:3000/x/connection/callback") { assert X::Config.valid_redirect? }
  end

  test "expired browser authorization never reaches the token endpoint" do
    with_config do |http|
      query = start_connection
      travel 11.minutes do
        get callback_x_connection_path, params: {state: query.fetch("state"), code: "test-code"}
        assert_redirected_to settings_path
      end
      assert_empty http.requests
    end
  end

  test "confidential clients authenticate token exchange without exposing secrets" do
    with_config([response_json(tokens)], client_secret: "private-client-secret") do |http|
      X::Client.new.exchange(code: "test-code", verifier: "test-verifier", redirect_uri: X::Config.redirect_uri)
      header = http.requests.first["Authorization"]
      assert_equal "Basic " + Base64.strict_encode64("test-client:private-client-secret"), header
      assert_not URI.decode_www_form(http.requests.first.body).to_h.key?("client_secret")
    end
  end

  test "identity read errors do not falsely connect the account" do
    with_config([response_json(tokens), response_json({}, code: 402)]) do
      query = start_connection
      get callback_x_connection_path, params: {state: query.fetch("state"), code: "test-code"}
      assert_redirected_to settings_path
      assert_nil X::Connection.current
      assert_includes flash[:alert], "credit balance"
    end
  end

  test "saved credential UI never includes decrypted tokens" do
    with_config do
      X::Connection.connect!(tokens, {"id" => "999", "username" => "owner"})
      get settings_path
      assert_response :success
      assert_not_includes response.body, "test-access"
      assert_not_includes response.body, "test-refresh"
      assert_includes response.body, "Credentials saved"
    end
  end

  test "a scope omitted as unchanged retains the requested read scopes" do
    without_scope = tokens.except("scope")
    with_config([response_json(without_scope), response_json({data: {id: "999", username: "owner"}})]) do
      query = start_connection
      get callback_x_connection_path, params: {state: query.fetch("state"), code: "test-code"}
      assert_equal X::Config::SCOPES.sort, X::Connection.current.granted_scopes.split.sort
    end
  end

  test "environment client configuration selects all its values" do
    environment = {"X_CLIENT_ID" => "env-client", "X_CLIENT_SECRET" => nil, "X_REDIRECT_URI" => "https://www.example.com/x/connection/callback"}
    previous = ENV.method(:[])
    ENV.stub(:[], ->(key) { environment.key?(key) ? environment[key] : previous.call(key) }) do
      assert_equal :environment, X::Config.source
      assert_equal "env-client", X::Config.client_id
      assert_nil X::Config.client_secret
    end
  end

  test "signing in with X pins an allowed handle, connects X, and records the identity read" do
    sign_out
    @user.update!(x_user_id: nil)
    with_config([response_json(tokens), response_json({data: {id: "999", username: "Owner"}})]) do
      query = start_connection
      get callback_x_connection_path, params: {state: query.fetch("state"), code: "test-code"}
      assert_redirected_to root_url
      assert_equal "999", @user.reload.x_user_id
      assert_equal "owner", X::Connection.current.username.downcase
      read = X::Read.sole
      assert_equal ["identity", "committed", 10_000], [read.dataset, read.status, read.estimated_micros]
      get people_path
      assert_response :success
    end
  end

  test "X accounts that aren't allowed never get a session or saved tokens" do
    sign_out
    with_config([response_json(tokens), response_json({data: {id: "555", username: "stranger"}})]) do
      query = start_connection
      get callback_x_connection_path, params: {state: query.fetch("state"), code: "test-code"}
      assert_redirected_to new_session_path
      assert_equal "@stranger isn't allowed to sign in.", flash[:alert]
      assert_nil X::Connection.current
      assert_equal 0, X::Read.count
      get people_path
      assert_redirected_to new_session_path
    end
  end

  test "a pinned account keeps access after renaming, and its old handle doesn't let others in" do
    assert_equal @user, User.for_x_identity("id" => "999", "username" => "Renamed")
    assert_equal "renamed", @user.reload.x_handle
    assert_nil User.for_x_identity("id" => "555", "username" => "renamed")
    @user.update!(x_handle: "owner")
    assert_nil User.for_x_identity("id" => "555", "username" => "owner")
  end

  test "favicon resolves to the local icon" do
    get "/favicon.ico"
    assert_redirected_to "/icon.svg"
  end

end
