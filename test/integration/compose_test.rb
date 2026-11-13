require "test_helper"

class ComposeTest < ActionDispatch::IntegrationTest
  test "capture an idea, open it, and move it across the board" do
    post drafts_path, params: { draft: { body: "Why SQLite is enough for a personal CRM", topic: "Local-first personal data" } }
    draft = Draft.last
    assert_equal "idea", draft.status
    get drafts_path
    assert_response :success
    assert_includes response.body, "Why SQLite is enough"
    assert_select "nav[aria-label=Compose] a[aria-current=page]", text: /Open/
    assert_select "nav[aria-label=Compose] a[href='#{ideas_drafts_path}']", text: "Inspiration"
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

  test "the composer saves thread posts, versions can be added, used, and deleted, and history restores" do
    post drafts_path, params: { draft: { parts: [ "First idea", "" ] } }
    draft = Draft.last
    assert_equal "First idea", draft.body
    get drafts_path
    assert_select "#draft_#{draft.id}", text: /First idea/
    patch draft_path(draft), params: { draft: { parts: [ "Hook", "  ", "Payoff" ] } }
    assert_equal [ "Hook", "Payoff" ], draft.reload.parts

    post draft_alternatives_path(draft), params: { alternative: { body: "A punchier hook" } }
    alternative = draft.alternatives.last
    get edit_draft_path(draft)
    assert_select "#alternatives", text: /A punchier hook/
    assert_select "#alternatives button[aria-label='Use this version']"
    assert_select "#alternatives button[aria-label='Delete this version']"
    post draft_alternative_promotion_path(draft, alternative)
    assert_equal "A punchier hook", draft.reload.body
    assert_equal [ "Hook\n\n---\n\nPayoff" ], draft.alternatives.map(&:body)

    travel 11.minutes do
      revision = draft.revisions.find_by(body: "Hook\n\n---\n\nPayoff")
      post draft_revision_restoration_path(draft, revision)
      assert draft.reload.thread?
    end
    delete draft_alternative_path(draft, draft.alternatives.first)
    assert_empty draft.alternatives.reload
  end
end
