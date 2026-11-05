require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  test "new workspaces default to a ten dollar allowance" do
    assert_equal 1000, Workspace.new.monthly_budget_cents
  end

  test "API allowance requires bounded integer cents" do
    workspace = Current.workspace
    [nil, "", -1, "10.50", "invalid", 100001].each do |value|
      workspace.monthly_budget_cents = value
      assert_not workspace.valid?, "Expected #{value.inspect} to be rejected"
    end
    [0, 1000, "1025", 100000].each do |value|
      workspace.monthly_budget_cents = value
      assert workspace.valid?, workspace.errors.full_messages.to_sentence
    end
  end
end
