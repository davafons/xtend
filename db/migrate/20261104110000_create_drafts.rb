class CreateDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :drafts do |t|
      t.text :body, null: false, default: ""
      t.string :status, null: false, default: "idea"
      t.string :topic
      t.text :notes
      t.string :inspiration_url
      t.string :posted_x_id
      t.datetime :posted_at
      t.timestamps
    end
    add_index :drafts, :status
    add_index :drafts, :posted_x_id, unique: true
  end
end
