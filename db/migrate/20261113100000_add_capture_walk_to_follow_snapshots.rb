class AddCaptureWalkToFollowSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :follow_snapshots, :next_cursor, :string
    add_column :follow_snapshots, :expected_count, :integer
    add_column :follow_snapshots, :last_page_at, :datetime
    add_column :workspaces, :owner_followers_count, :integer
    add_column :workspaces, :owner_following_count, :integer
    add_column :workspaces, :owner_counts_seen_at, :datetime
    add_column :reply_events, :dismissed_at, :datetime
  end
end
