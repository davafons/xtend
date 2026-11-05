class CreateArchiveImports < ActiveRecord::Migration[8.1]
  def change
    create_table :archive_imports do |t|
      t.string :owner_x_id, null: false
      t.datetime :generated_at, null: false
      t.datetime :account_created_at, null: false
      t.boolean :partial, default: false, null: false
      t.integer :direct_messages_count, default: 0, null: false
      t.integer :skipped_count, default: 0, null: false
      t.timestamps
    end

    add_column :direct_messages, :source, :string, default: "x_api", null: false
    change_column_null :direct_messages, :x_sync_run_id, true
  end
end
