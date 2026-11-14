class LetAIApplyChanges < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :mcp_apply_changes, :boolean, default: true, null: false
    # What an applied proposal changed, so undoing it reverses exactly that.
    add_column :ai_proposals, :applied, :json, default: {}, null: false
    add_column :ai_proposals, :undone_at, :datetime
  end
end
