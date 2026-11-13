# since_id was read for every page but never set, and last_snapshot_id was set but never read: a follower period's
# last_seen_at already says when it was last seen. builder_interests defaulted to the first owner's own topics;
# new workspaces now start empty and fill them in Settings.
class DropUnusedColumns < ActiveRecord::Migration[8.1]
  def change
    remove_column :x_sync_runs, :since_id, :string
    remove_reference :follower_periods, :last_snapshot, foreign_key: { to_table: :follow_snapshots }, index: true
    change_column_default :workspaces, :builder_interests,
      from: "AI agents and coding tools\nBuilding and shipping Rails products\nDeveloper workflows\nJapanese learning tools\nLocal-first personal data", to: ""
  end
end
