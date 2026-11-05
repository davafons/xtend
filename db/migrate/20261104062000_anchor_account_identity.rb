class AnchorAccountIdentity < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :owner_x_id, :string
    add_index :daily_sessions, "(1)", unique: true, where: "completed_at IS NULL", name: "index_one_active_daily_session"
  end
end
