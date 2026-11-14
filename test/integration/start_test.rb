require "test_helper"
require "zip"

class StartTest < ActionDispatch::IntegrationTest
  test "a new workspace opens on Get started, and each step ticks itself from what Xtend sees" do
    get root_path
    assert_select "a[href=?]", start_path, text: "Get started"
    get start_path
    assert_select "h1", "Get started"
    assert_select "#step-archive h2", text: /To do:Import your X archive/
    assert_select "#step-extension code", text: "http://www.example.com"
    assert_select "nav a[href=?]", start_path

    Oauth::Grant.paste!(workspace: Current.workspace, user: nil, scope: "capture")
    X::AccountDay.create!(day: Date.yesterday, observed_at: Time.current, counts: {})
    get start_path
    assert_select "#step-extension h2", text: /Done:Install the browser extension/
    assert_select "#step-analytics h2", text: /Done:/
    assert_select "#step-ai h2", text: /To do:.*optional/m
  end

  test "the extension downloads as a zip of the extension folder" do
    get extension_path
    assert_response :success
    assert_equal "application/zip", response.media_type
    names = Zip::File.open_buffer(StringIO.new(response.body)).entries.map(&:name)
    assert_includes names, "xtend-extension/manifest.json"
    assert_includes names, "xtend-extension/icons/icon-128.png"
    assert names.none? { _1.include?("node_modules") }
  end
end
