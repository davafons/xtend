require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  PUBLIC = { "sessions#new" => :success, "sessions#create" => :not_found, "rails/health#show" => :success,
    "x/connections#create" => :redirect, "x/connections#callback" => :redirect,
    "mcp/endpoints#create" => :unauthorized, "mcp/endpoints#unsupported" => :unauthorized,
    "x/captures#create" => :unauthorized,
    "oauth/metadata#authorization_server" => :success, "oauth/metadata#protected_resource" => :success,
    "oauth/registrations#create" => :bad_request, "oauth/tokens#create" => :unauthorized, "oauth/tokens#revoke" => :unauthorized }.freeze

  setup { sign_out }

  test "every route except X sign-in, the health check, OAuth discovery and token exchange, and the token-protected MCP and capture endpoints requires a session" do
    routes = Rails.application.routes.routes.filter_map do |route|
      next if route.verb.blank? || route.defaults[:controller].nil? || route.defaults[:controller].start_with?("turbo/", "action_mailbox/", "active_storage/") || route.defaults[:controller].start_with?("rails/") && route.defaults[:controller] != "rails/health"
      [ route.verb.split("|").first.downcase, route.path.spec.to_s.sub("(.:format)", "").gsub(%r{\(/\*\w+\)}, "").gsub(/:\w+/, "1"), "#{route.defaults[:controller]}##{route.defaults[:action]}" ]
    end
    assert_operator routes.size, :>, 30
    routes.each do |verb, path, action|
      send(verb, path)
      if PUBLIC.key?(action)
        assert_response PUBLIC.fetch(action), "#{verb.upcase} #{path} (#{action})"
      else
        assert_redirected_to new_session_path, "#{verb.upcase} #{path} (#{action}) must require sign-in"
      end
    end
  end

  test "the sign-in page offers only X, and signing out ends the session" do
    get people_path
    assert_redirected_to new_session_path
    follow_redirect!
    assert_includes response.body, "Sign in with X"
    assert_not_includes response.body, 'type="password"'

    sign_in_as(@user)
    get people_path
    assert_response :success
    delete session_path
    assert_redirected_to new_session_path
    get people_path
    assert_redirected_to new_session_path
  end

  test "old sessions expire" do
    old = @user.sessions.create!(created_at: Session::LIFETIME.ago - 1.day)
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = old.id
    cookies["session_id"] = jar[:session_id]
    get root_path
    assert_redirected_to new_session_path
  end

  test "the demo workspace opens without X, and only in demo mode" do
    post session_path
    assert_response :not_found
    original = Rails.configuration.x.demo
    Rails.configuration.x.demo = true
    post session_path
    assert_redirected_to root_path
    get people_path
    assert_response :success
  ensure
    Rails.configuration.x.demo = original
  end

  test "a signed-in user sees only their own workspace" do
    other = Workspace.create!(name: "Other")
    Current.set(workspace: other) { Person.create!(handle: "theirs", name: "Their Contact") }
    intruder = other.users.create!(x_handle: "other")
    sign_in_as(intruder)
    get people_path
    assert_includes response.body, "Their Contact"
    sign_in_as(@user)
    get people_path
    assert_not_includes response.body, "Their Contact"
  end
end
