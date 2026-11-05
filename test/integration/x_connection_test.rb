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
    {"access_token" => "test-access", "refresh_token" => "test-refresh", "token_type" => "bearer", "expires_in" => 7200, "scope" => XConfig::SCOPES.join(" ")}.merge(overrides.stringify_keys)
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
      TokenVault.stub(:key_path, Pathname.new(directory).join("x-token.key")) do
        XConfig.stub(:client_id, "test-client") do
          XConfig.stub(:client_secret, client_secret) do
            XConfig.stub(:redirect_uri, "https://www.example.com/x/connection/callback") do
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
      assert_equal XConfig::SCOPES.sort, query.fetch("scope").split.sort
      assert_equal "S256", query.fetch("code_challenge_method")
      assert_not_includes query, "code_verifier"
      get x_connection_callback_path, params: {state: query.fetch("state"), code: "test-code"}
      assert_redirected_to settings_path
      connection = XConnection.current
      assert_equal "999", connection.x_user_id
      assert_equal "owner", connection.username
      assert_not_includes connection.token_ciphertext, "test-access"
      assert_not_includes connection.token_ciphertext, "test-refresh"
      assert_equal 0o600, File.stat(TokenVault.key_path).mode & 0o777
      assert_equal "999", Workspace.current.owner_x_id
      assert_equal ["/2/oauth2/token", "/2/users/me"], http.requests.map(&:path)
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
      get x_connection_callback_path, params: {state: "wrong", code: "test-code"}
      assert_redirected_to settings_path
      get x_connection_callback_path, params: {state: query.fetch("state"), code: "test-code"}
      assert_redirected_to settings_path
      assert_empty http.requests
      assert_nil XConnection.current
    end
  end

  test "expired and single-use authorizations are enforced server-side" do
    attempt, state = XAuthorization.start!
    assert_not XAuthorization.consume!(attempt.id, "incorrect")
    assert XAuthorization.consume!(attempt.id, state)
    assert_not XAuthorization.consume!(attempt.id, state)
    attempt, state = XAuthorization.start!
    travel 11.minutes do
      assert_not XAuthorization.consume!(attempt.id, state)
    end
  end

  test "provider denial makes no API requests" do
    with_config do |http|
      query = start_connection
      get x_connection_callback_path, params: {state: query.fetch("state"), error: "access_denied"}
      assert_redirected_to settings_path
      assert_empty http.requests
      assert_nil XConnection.current
    end
  end

  test "a different X account cannot replace this workspace owner" do
    with_config([response_json(tokens), response_json({data: {id: "888", username: "different"}})]) do
      query = start_connection
      get x_connection_callback_path, params: {state: query.fetch("state"), code: "test-code"}
      assert_redirected_to settings_path
      assert_nil XConnection.current
      assert_equal "999", Workspace.current.owner_x_id
    end
  end

  test "extra write scope is rejected" do
    with_config([response_json(tokens(scope: XConfig::SCOPES.join(" ") + " tweet.write")), response_json({data: {id: "999", username: "owner"}})]) do
      query = start_connection
      get x_connection_callback_path, params: {state: query.fetch("state"), code: "test-code"}
      assert_nil XConnection.current
    end
  end

  test "refresh rotation persists even if the following identity read fails" do
    with_config([response_json(tokens(access_token: "rotated-access", refresh_token: "rotated-refresh")), response_json({}, code: 503)]) do |http|
      connection = XConnection.connect!(tokens, {"id" => "999", "username" => "owner"})
      connection.update!(expires_at: 1.minute.ago)
      assert_raises(XClient::Error) { connection.check_identity! }
      stored = JSON.parse(TokenVault.decrypt(connection.reload.token_ciphertext))
      assert_equal "rotated-refresh", stored.fetch("refresh_token")
      assert connection.expires_at > Time.current
      assert_equal ["/2/oauth2/token", "/2/users/me"], http.requests.map(&:path)
    end
  end

  test "checking a valid connection reads only identity and disconnect preserves people" do
    with_config([response_json({data: {id: "999", username: "renamed"}})]) do |http|
      XConnection.connect!(tokens, {"id" => "999", "username" => "owner"})
      person = Person.create!(handle: "builder", name: "Builder", notes: "Keep my note")
      patch x_connection_path
      assert_redirected_to settings_path
      assert_equal "renamed", XConnection.current.username
      assert_equal ["/2/users/me"], http.requests.map(&:path)
      delete x_connection_path
      assert_nil XConnection.current
      assert_equal "Keep my note", person.reload.notes
      assert_equal "999", Workspace.current.owner_x_id
      assert_equal 1, http.requests.size
    end
  end

  test "missing config refuses connection and demo cannot authorize X" do
    XConfig.stub(:client_id, nil) do
      post x_connection_path
      assert_redirected_to settings_path
    end
    original = Rails.configuration.x.demo
    Rails.configuration.x.demo = true
    with_config do |http|
      post x_connection_path
      assert_redirected_to settings_path
      assert_empty http.requests
      assert_nil XConnection.current
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
      XConfig.stub(:redirect_uri, uri) { assert_not XConfig.valid_redirect? }
    end
    XConfig.stub(:redirect_uri, "http://127.0.0.1:3000/x/connection/callback") { assert XConfig.valid_redirect? }
  end

  test "expired browser authorization never reaches the token endpoint" do
    with_config do |http|
      query = start_connection
      travel 11.minutes do
        get x_connection_callback_path, params: {state: query.fetch("state"), code: "test-code"}
        assert_redirected_to settings_path
      end
      assert_empty http.requests
    end
  end

  test "confidential clients authenticate token exchange without exposing secrets" do
    with_config([response_json(tokens)], client_secret: "private-client-secret") do |http|
      XClient.new.exchange(code: "test-code", verifier: "test-verifier", redirect_uri: XConfig.redirect_uri)
      header = http.requests.first["Authorization"]
      assert_equal "Basic " + Base64.strict_encode64("test-client:private-client-secret"), header
      assert_not URI.decode_www_form(http.requests.first.body).to_h.key?("client_secret")
    end
  end

  test "identity read errors do not falsely connect the account" do
    with_config([response_json(tokens), response_json({}, code: 402)]) do
      query = start_connection
      get x_connection_callback_path, params: {state: query.fetch("state"), code: "test-code"}
      assert_redirected_to settings_path
      assert_nil XConnection.current
      assert_includes flash[:alert], "credit balance"
    end
  end

  test "saved credential UI never includes decrypted tokens" do
    with_config do
      XConnection.connect!(tokens, {"id" => "999", "username" => "owner"})
      get settings_path
      assert_response :success
      assert_not_includes response.body, "test-access"
      assert_not_includes response.body, "test-refresh"
      assert_includes response.body, "Credentials saved"
    end
  end

  def with_local_config(responses = [])
    https!
    host! "www.example.com"
    http = MockHTTP.new(responses)
    Dir.mktmpdir("crm-local-config-test") do |directory|
      TokenVault.stub(:key_path, Pathname.new(directory).join("x-token.key")) do
        XConfig.stub(:source, -> { XClientConfiguration.current ? :local : :none }) do
          Net::HTTP.stub(:start, ->(*args, **options, &block) { block.call(http) }) { yield http }
        end
      end
    end
  end

  def local_values(**overrides)
    {client_id: "local-client", client_secret: "private-local-secret", redirect_uri: "https://www.example.com/x/connection/callback"}.merge(overrides)
  end

  test "local configuration is encrypted and saved secrets never render" do
    with_local_config do |http|
      patch x_client_configuration_path, params: {x_client_configuration: local_values}
      assert_redirected_to settings_path
      record = XClientConfiguration.current
      assert_equal "private-local-secret", record.values[:client_secret]
      assert_not_includes record.settings_ciphertext, "private-local-secret"
      assert_not_includes record.settings_ciphertext, "local-client"
      assert_nil TokenVault.decrypt(record.settings_ciphertext)
      assert_equal :local, XConfig.source
      get settings_path
      assert_response :success
      assert_includes response.body, 'type="password"'
      assert_not_includes response.body, "private-local-secret"
      get context_export_path
      assert_not_includes response.body, "private-local-secret"
      assert_not_includes response.body, "settings_ciphertext"
      assert_empty http.requests
    end
  end

  test "local configuration requires the browser CSRF token" do
    with_local_config do
      previous = XClientConfigurationsController.allow_forgery_protection
      XClientConfigurationsController.allow_forgery_protection = true
      patch x_client_configuration_path, params: {x_client_configuration: local_values}
      assert_response :unprocessable_content
      assert_nil XClientConfiguration.current
    ensure
      XClientConfigurationsController.allow_forgery_protection = previous
    end
  end

  test "invalid callback configuration is not stored and never echoes secrets" do
    with_local_config do
      patch x_client_configuration_path, params: {x_client_configuration: local_values(redirect_uri: "https://www.example.com/wrong")}
      assert_redirected_to settings_path
      assert_nil XClientConfiguration.current
      assert_not_includes flash[:alert], "private-local-secret"
    end
  end

  test "an active connection protects local configuration" do
    with_local_config do
      XClientConfiguration.store!(local_values)
      XConnection.connect!(tokens, {"id" => "999", "username" => "owner"})
      ciphertext = XClientConfiguration.current.settings_ciphertext
      patch x_client_configuration_path, params: {x_client_configuration: local_values(client_secret: "replacement")}
      assert_equal ciphertext, XClientConfiguration.current.settings_ciphertext
      assert_equal 1, XConnection.count
      assert_includes flash[:alert], "Disconnect"
      get settings_path
      assert_not_includes response.body, "private-local-secret"
    end
  end

  test "saving configuration invalidates pending browser authorization" do
    with_local_config do |http|
      XClientConfiguration.store!(local_values)
      query = start_connection
      patch x_client_configuration_path, params: {x_client_configuration: local_values(client_secret: "replacement")}
      get x_connection_callback_path, params: {state: query.fetch("state"), code: "old-code"}
      assert_redirected_to settings_path
      assert_nil XConnection.current
      assert_empty http.requests
    end
  end

  test "configuration changes during callback cannot save the old tokens" do
    changed_identity = ->(_) do
      XClientConfiguration.store!(local_values(client_secret: "replacement"))
      response_json({data: {id: "999", username: "owner"}})
    end
    with_local_config([response_json(tokens), changed_identity]) do
      XClientConfiguration.store!(local_values)
      query = start_connection
      get x_connection_callback_path, params: {state: query.fetch("state"), code: "test-code"}
      assert_nil XConnection.current
      assert_includes flash[:alert], "configuration changed"
    end
  end

  test "blank secret preserves only the same client and explicit clear removes it" do
    with_local_config do
      XClientConfiguration.store!(local_values)
      XClientConfiguration.store!(local_values(client_secret: ""))
      assert_equal "private-local-secret", XClientConfiguration.current.values[:client_secret]
      XClientConfiguration.store!(local_values(client_secret: "", clear_client_secret: "1"))
      assert_equal "", XClientConfiguration.current.values[:client_secret]
      XClientConfiguration.store!(local_values)
      XClientConfiguration.store!(local_values(client_id: "different-client", client_secret: ""))
      assert_equal "", XClientConfiguration.current.values[:client_secret]
    end
  end

  test "environment client configuration never borrows a local app secret" do
    Dir.mktmpdir("crm-source-test") do |directory|
      TokenVault.stub(:key_path, Pathname.new(directory).join("key")) do
        XClientConfiguration.store!(local_values)
        previous = ENV.method(:[])
        environment = {"X_CLIENT_ID" => "env-client", "X_CLIENT_SECRET" => nil, "X_REDIRECT_URI" => "https://www.example.com/x/connection/callback"}
        ENV.stub(:[], ->(key) { environment.key?(key) ? environment[key] : previous.call(key) }) do
          assert_equal :environment, XConfig.source
          assert_equal "env-client", XConfig.client_id
          assert_nil XConfig.client_secret
        end
      end
    end
  end

  test "local configuration refuses remote requests" do
    with_local_config do
      patch x_client_configuration_path, params: {x_client_configuration: local_values}, headers: {"REMOTE_ADDR" => "203.0.113.10"}
      assert_response :forbidden
      assert_nil XClientConfiguration.current
    end
  end

  test "a scope omitted as unchanged retains the requested read scopes" do
    without_scope = tokens.except("scope")
    with_config([response_json(without_scope), response_json({data: {id: "999", username: "owner"}})]) do
      query = start_connection
      get x_connection_callback_path, params: {state: query.fetch("state"), code: "test-code"}
      assert_equal XConfig::SCOPES.sort, XConnection.current.granted_scopes.split.sort
    end
  end

  test "local secret fields are filtered in nested parameters" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    result = filter.filter({"x_client_configuration" => {"client_secret" => "private-local-secret"}})
    assert_equal "[FILTERED]", result.fetch("x_client_configuration").fetch("client_secret")
  end

  test "favicon resolves to the local icon" do
    get "/favicon.ico"
    assert_redirected_to "/icon.svg"
  end

end
