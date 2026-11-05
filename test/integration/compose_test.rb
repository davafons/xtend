require "test_helper"

class ComposeTest < ActionDispatch::IntegrationTest
  test "capture an idea, open it, and move it across the board" do
    post drafts_path, params: { draft: { body: "Why SQLite is enough for a personal CRM", topic: "Local-first personal data" } }
    draft = Draft.last
    assert_equal "idea", draft.status
    get drafts_path
    assert_response :success
    assert_includes response.body, "Why SQLite is enough"
    patch draft_path(draft), params: { draft: { status: "drafting" }, return_to: "board" }
    assert_redirected_to drafts_path
    get edit_draft_path(draft)
    assert_response :success
    patch draft_path(draft), params: { draft: { body: "Updated\n---\nSecond part" } }
    assert_redirected_to edit_draft_path(draft)
    assert draft.reload.thread?
  end

  test "new drafts from ideas open the composer, and ideas render from saved data" do
    post drafts_path, params: { open: "1", draft: { status: "drafting", notes: "Question from @someone: how do you back up SQLite?", inspiration_url: "https://x.com/i/status/1" } }
    assert_redirected_to edit_draft_path(Draft.last)
    get ideas_drafts_path
    assert_response :success
    assert_includes response.body, "Copy Grok prompt"
    get new_draft_path
    assert_response :success
  end

  test "invalid inspiration links are rejected" do
    assert_no_difference "Draft.count" do
      post drafts_path, params: { draft: { body: "x", inspiration_url: "javascript:alert(1)" } }
    end
  end
end
