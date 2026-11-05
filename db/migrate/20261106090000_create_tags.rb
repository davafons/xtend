class CreateTags < ActiveRecord::Migration[8.1]
  def change
    create_table :tags do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
    add_index :tags, [ :workspace_id, :name ], unique: true

    create_table :person_tags do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.string :source, null: false, default: "owner"
      t.timestamps
    end
    add_index :person_tags, [ :person_id, :tag_id ], unique: true
  end
end
