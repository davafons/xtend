class CreateXAnalytics < ActiveRecord::Migration[8.1]
  def change
    # One day of X's account analytics: counts per engagement type, split by whether the engaging account is verified.
    create_table :x_account_days do |t|
      t.references :workspace, null: false, foreign_key: true
      t.date :day, null: false
      t.json :counts, null: false, default: {}
      t.datetime :observed_at, null: false
      t.timestamps
    end
    add_index :x_account_days, %i[workspace_id day], unique: true

    # A post's private totals from X's analytics Content tab.
    create_table :x_post_analytics do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :post_x_id, null: false
      t.datetime :published_at
      t.text :body
      t.json :metrics, null: false, default: {}
      t.datetime :observed_at, null: false
      t.timestamps
    end
    add_index :x_post_analytics, %i[workspace_id post_x_id], unique: true
  end
end
