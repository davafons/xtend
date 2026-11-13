# Reply candidates, counted targets, and sessions all belong to Outreach. A session no longer waits to be
# finished by hand: it ends once it goes quiet, so one per workspace and day.
class GatherOutreachTables < ActiveRecord::Migration[8.1]
  def change
    rename_table :posts, :outreach_candidates
    rename_table :outreaches, :outreach_targets
    rename_table :daily_sessions, :outreach_sessions
    rename_column :outreach_targets, :daily_session_id, :outreach_session_id
    remove_index :outreach_sessions, :workspace_id, name: "index_one_active_daily_session", unique: true, where: "completed_at IS NULL"
    remove_column :outreach_sessions, :completed_at, :datetime
    add_index :outreach_sessions, [ :workspace_id, :anchor_day ], unique: true
  end
end
