require "test_helper"

class WorkspaceIsolationTest < ActiveSupport::TestCase
  setup do
    @mine = Current.workspace
    @other = Workspace.create!(name: "Other", owner_x_id: "888")
  end

  def in_other(&block) = Current.set(workspace: @other, &block)

  test "the same X records can exist in two workspaces and each sees only its own" do
    ingest(person_profile: profile(x_id: "555", handle: "shared"), x_id: "7001", target_x_id: "8001")
    in_other do
      ingest(person_profile: profile(x_id: "555", handle: "shared", name: "Other view"), x_id: "7001", target_x_id: "8001")
      assert_equal [ "Other view" ], Person.pluck(:name)
      assert_equal 1, ReplyEvent.count
    end
    assert_equal [ "A Builder" ], Person.pluck(:name)
    assert_equal 2, Person.unscoped.count
    assert_equal 1, Outreach::Session.current.progress
  end

  test "associations, subqueries, and AI checks never cross workspaces" do
    ingest(person_profile: profile(x_id: "555", handle: "shared"), x_id: "7001", target_x_id: "8101")
    in_other do
      result = AI::Intake.new(via: "mcp").call("posts" => [ { "url" => "https://x.com/shared/status/8101", "text" => "A question",
        "published_at" => 1.hour.ago.iso8601 } ])
      assert_equal "created", result[:posts].first[:status], "another workspace's reply must not mark this post replied"
      assert_includes Outreach::Candidate.opportunities.map(&:x_id), "8101"
    end
    assert_not_includes Outreach::Candidate.opportunities.map(&:x_id), "8101"
    assert_empty Person.find_by!(handle: "shared").outreach_candidates
  end

  test "queries without a workspace raise instead of returning everyone's data" do
    Current.reset
    assert_raises(Current::MissingWorkspace) { Person.count }
    assert_raises(Current::MissingWorkspace) { Person.new(handle: "x", name: "x").save! }
  end

  test "each workspace's connector token reaches only that workspace" do
    token = paste_token("mcp", workspace: @other)
    assert_equal @other, Oauth::Grant.authenticate(token, scope: "mcp").workspace
    assert_nil Oauth::Grant.authenticate("xtend_unknown", scope: "mcp")
    assert_nil Oauth::Grant.authenticate(nil, scope: "mcp")
  end
end
