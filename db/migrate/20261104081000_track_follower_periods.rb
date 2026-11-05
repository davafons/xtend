class TrackFollowerPeriods < ActiveRecord::Migration[8.1]
  def change
    add_column :follow_snapshots, :follower_tracking_completed_at, :datetime
    create_table :follower_periods do |t|
      t.references :person, null: false, foreign_key: true
      t.references :first_snapshot, null: false, foreign_key: { to_table: :follow_snapshots }
      t.references :last_snapshot, null: false, foreign_key: { to_table: :follow_snapshots }
      t.references :ended_snapshot, foreign_key: { to_table: :follow_snapshots }
      t.datetime :followed_after
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :ended_by
      t.timestamps
    end
    add_index :follower_periods, :person_id, unique: true, where: "ended_by IS NULL", name: "one_open_follow_period_per_person"
    add_index :follower_periods, [ :person_id, :first_snapshot_id ], unique: true
  end
end
