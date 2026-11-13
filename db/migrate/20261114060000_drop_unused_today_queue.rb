# The old Today queue's skip/snooze, hand-reported replies, and pasted discovery links have had no UI since
# Outreach replaced it. Reply confirmation comes from captures and syncs instead.
class DropUnusedTodayQueue < ActiveRecord::Migration[8.1]
  def change
    drop_table :reply_reports do |t|
      t.references :post, null: false, index: { unique: true }
      t.string :reply_url
      t.references :workspace, null: false
      t.timestamps
    end
    drop_table :post_dispositions do |t|
      t.references :post, null: false, index: { unique: true }
      t.string :kind, null: false
      t.datetime :until_at
      t.references :workspace, null: false
      t.timestamps
    end
    drop_table :discovery_suggestions do |t|
      t.string :post_x_id, null: false
      t.string :source_url, null: false
      t.string :match_reason
      t.datetime :dismissed_at
      t.references :workspace, null: false
      t.timestamps
    end
  end
end
