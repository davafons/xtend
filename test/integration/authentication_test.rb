require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  PUBLIC = { "sessions#new" => :success, "sessions#create" => :redirect, "rails/health#show" => :success,
    "mcp/endpoints#create" => :unauthorized, "mcp/endpoints#unsupported" => :unauthorized }.freeze

  setup { sign_out }

  test "every route except sign-in, the health check, and the token-protected MCP endpoint requires a session" do
    routes = Rails.application.routes.routes.filter_map do |route|
      next if route.verb.blank? || route.defaults[:controller].nil? || route.defaults[:controller].start_with?("turbo/", "action_mailbox/", "active_storage/") || route.defaults[:controller].start_with?("rails/") && route.defaults[:controller] != "rails/health"
      [ route.verb.split("|").first.downcase, route.path.spec.to_s.sub("(.:format)", "").gsub(/:\w+/, "1"), "#{route.defaults[:controller]}##{route.defaults[:action]}" ]
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

  test "signing in returns to the requested page, and signing out ends the session" do
    get people_path
    assert_redirected_to new_session_path
    follow_redirect!
    assert_includes response.body, "Sign in"
    post session_path, params: { email_address: "OWNER@example.com ", password: "correct horse battery" }
    assert_redirected_to people_url
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Sign out"

    delete session_path
    assert_redirected_to new_session_path
    get people_path
    assert_redirected_to new_session_path
  end

  test "wrong passwords fail, attempts are rate limited, and old sessions expire" do
    post session_path, params: { email_address: "owner@example.com", password: "wrong password!" }
    assert_redirected_to new_session_path(email_address: "owner@example.com")
    get root_path
    assert_redirected_to new_session_path

    old = @user.sessions.create!(created_at: 31.days.ago)
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = old.id
    cookies["session_id"] = jar[:session_id]
    get root_path
    assert_redirected_to new_session_path

    9.times { post session_path, params: { email_address: "owner@example.com", password: "wrong" } }
    post session_path, params: { email_address: "owner@example.com", password: "correct horse battery" }
    assert_equal "Too many sign-in attempts. Try again in a few minutes.", flash[:alert]
  end

  test "a signed-in user sees only their own workspace" do
    other = Workspace.create!(name: "Other")
    Current.set(workspace: other) { Person.create!(handle: "theirs", name: "Their Contact") }
    intruder = other.users.create!(email_address: "other@example.com", password: "another long password")
    sign_in_as(intruder)
    get people_path
    assert_includes response.body, "Their Contact"
    sign_in_as(@user)
    get people_path
    assert_not_includes response.body, "Their Contact"
  end
end
