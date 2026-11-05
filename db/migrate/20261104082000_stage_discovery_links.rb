class StageDiscoveryLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :discovery_suggestions do |t|
      t.string :post_x_id, null: false
      t.string :source_url, null: false
      t.text :match_reason
      t.datetime :dismissed_at
      t.timestamps
    end
    add_index :discovery_suggestions, :post_x_id, unique: true
  end
end
