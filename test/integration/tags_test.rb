require "test_helper"

class TagsTest < ActionDispatch::IntegrationTest
  setup do
    @person = Person.resolve_profile!(profile)
    @other = Person.resolve_profile!(profile(x_id: "102", handle: "plain", name: "Plain Person"))
  end

  test "the owner adds and removes tags on the person page and filters People by tag" do
    post person_tags_path(@person), params: { name: "Tokyo, ios dev" }
    assert_redirected_to person_path(@person)
    follow_redirect!
    assert_includes response.body, "#tokyo"
    get people_path(tag: "tokyo")
    assert_includes response.body, "A Builder"
    assert_not_includes response.body, "Plain Person"
    get people_path(filter: "untagged")
    assert_includes response.body, "Plain Person"
    assert_not_includes response.body, "A Builder"

    delete person_tag_path(@person, Tag.find_by!(name: "tokyo"))
    assert_equal ["ios dev"], @person.reload.tags.map(&:name)
  end

  test "with AI set to ask first, its tags wait on the AI page and can be accepted in bulk" do
    get ai_connector_path
    assert_includes response.body, "Run the Xtend task tag_people."
    assert_not_includes response.body, "ai_output"
    AI::Intake.new(via: "mcp", apply: false).call("tags" => [{ "handle" => "builder", "tags" => ["tokyo"] }, { "handle" => "plain", "tags" => ["designer"] }])
    get ai_connector_path
    assert_includes response.body, "2 people with suggested tags"
    patch review_ai_proposals_path, params: { decision: "accept" }
    assert_equal ["tokyo"], @person.reload.tags.map(&:name)
    assert_equal ["designer"], @other.reload.tags.map(&:name)
    assert_empty AI::Proposal.pending
  end

  test "the person page shows replies as a thread with the parent post" do
    ingest(x_id: "7001", target_x_id: "8001")
    get person_path(@person)
    assert_response :success
    assert_includes response.body, "You replied to A Builder"
    assert_includes response.body, "Text not collected"
  end
end
