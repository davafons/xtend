require "test_helper"

class WorkflowTest < ActionDispatch::IntegrationTest
  test "core pages and settings render with honest empty data" do
    [root_path, people_path, follow_reviews_path, settings_path, new_person_path].each do |path|
      get path
      assert_response :success
    end
    get context_export_path
    assert_response :success
    assert_equal "twitter-crm-context-v1", JSON.parse(response.body).fetch("format")
  end

  test "saving a person pin notes and keep uses real persistence" do
    post people_path, params: {person: {name: "Builder", handle: "builder"}}
    person = Person.last
    assert_redirected_to person_path(person)
    post person_pin_path(person)
    assert person.reload.pin
    patch person_path(person), params: {person: {notes: "We discussed testing", name: "Not permitted"}}
    assert_equal "We discussed testing", person.reload.notes
    assert_equal "Builder", person.name
    post person_follow_protection_path(person)
    assert person.reload.follow_protection
    delete person_pin_path(person)
    assert_nil person.reload.pin
  end

  test "API allowance is explicitly editable without changing connection or interests" do
    workspace = Current.workspace
    workspace.update!(monthly_budget_cents: 2500, builder_interests: "Builder tooling")
    patch settings_path, params: {workspace: {monthly_budget_cents: "1000"}}
    assert_redirected_to settings_path
    assert_equal 1000, workspace.reload.monthly_budget_cents
    assert_equal "Builder tooling", workspace.builder_interests
    assert_equal "999", workspace.owner_x_id
    get x_billing_cycles_path
    assert_response :success
    assert_includes response.body, "$10.00"
    assert_includes response.body, "cannot verify or change your X billing cap"
    get x_sources_path
    assert_includes response.body, "A continuation always needs another click"
  end

  test "invalid allowance is rejected without overwriting the saved amount" do
    workspace = Current.workspace
    workspace.update!(monthly_budget_cents: 1775)
    patch settings_path, params: {workspace: {monthly_budget_cents: "10.50"}}, headers: {"HTTP_REFERER" => x_billing_cycles_url}
    assert_redirected_to x_billing_cycles_url
    assert_equal 1775, workspace.reload.monthly_budget_cents
    follow_redirect!
    assert_includes response.body, "Monthly budget cents must be an integer"
  end

  test "manual reply report cannot advance confirmed progress" do
    person = Person.resolve_profile!(profile)
    tweet = person.posts.create!(x_id: "8001", body: "A useful question", published_at: 1.hour.ago)
    session = DailySession.current
    post post_reply_report_path(tweet), params: {confirmed: true, source: "x_api"}
    assert_redirected_to root_path
    assert_equal 1, ReplyReport.count
    assert_equal 0, session.reload.progress
    assert_equal 0, ReplyEvent.count
    delete post_reply_report_path(tweet)
    assert_equal 0, ReplyReport.count
  end

  test "wrong reply URL and bad import are handled without changing data" do
    person = Person.resolve_profile!(profile)
    tweet = person.posts.create!(x_id: "8001", body: "Question", published_at: 1.hour.ago)
    post post_reply_report_path(tweet), params: {reply_url: "javascript:alert(1)"}
    assert_equal 0, ReplyReport.count
    post discovery_imports_path
    assert_redirected_to discovery_path
    assert_equal 0, ReplyEvent.count
  end
  test "fictional demo renders populated views without live links" do
    original = Rails.configuration.x.demo
    Rails.configuration.x.demo = true
    DemoWorkspace.seed!
    assert_equal 12, DailySession.current.progress
    [root_path, people_path, follow_reviews_path, settings_path, discovery_path, x_sources_path, grok_connector_path, x_billing_cycles_path, person_path(Person.first)].each do |path|
      get path
      assert_response :success
    end
  ensure
    Rails.configuration.x.demo = original
  end

end
