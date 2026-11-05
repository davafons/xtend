class LowerDefaultApiAllowance < ActiveRecord::Migration[8.1]
  def change
    change_column_default :workspaces, :monthly_budget_cents, from: 2500, to: 1000
  end
end
