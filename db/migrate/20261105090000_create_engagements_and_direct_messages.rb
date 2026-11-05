class CreateEngagementsAndDirectMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :engagements do |t|
      t.string :kind, null: false
      t.string :post_x_id, null: false
      t.string :author_x_id, null: false
      t.text :body
      t.datetime :post_published_at, null: false
      t.datetime :observed_after
      t.datetime :observed_at, null: false
      t.references :x_sync_run, null: false, foreign_key: true
      t.timestamps
      t.index [:kind, :post_x_id], unique: true
      t.index :author_x_id
    end

    create_table :direct_messages do |t|
      t.string :x_id, null: false
      t.string :conversation_x_id, null: false
      t.string :partner_x_id, null: false
      t.string :direction, null: false
      t.datetime :occurred_at, null: false
      t.references :x_sync_run, null: false, foreign_key: true
      t.timestamps
      t.index :x_id, unique: true
      t.index [:partner_x_id, :occurred_at]
    end
  end
end
