class CreateXAnalyticsHoursAndSnapshots < ActiveRecord::Migration[8.1]
  def change
    # One hour of one metric from the heatmap on X's analytics Audience page.
    create_table :x_analytics_hours do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :metric, null: false
      t.datetime :hour, null: false
      t.integer :value, null: false, default: 0
      t.datetime :observed_at, null: false
      t.timestamps
    end
    add_index :x_analytics_hours, %i[workspace_id metric hour], unique: true

    # A figure X's analytics pages give for a whole range or for right now: who you reached (Audience) and your
    # active and verified followers (Overview).
    create_table :x_analytics_snapshots do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :kind, null: false
      t.date :from_on, null: false
      t.date :to_on, null: false
      t.json :data, null: false, default: {}
      t.datetime :observed_at, null: false
      t.timestamps
    end
    add_index :x_analytics_snapshots, %i[workspace_id kind from_on to_on], unique: true
  end
end
