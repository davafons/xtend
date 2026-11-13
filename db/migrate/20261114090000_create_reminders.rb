class CreateReminders < ActiveRecord::Migration[8.1]
  def change
    create_table :reminders do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.string :reason, null: false
      t.date :due_on, null: false
      t.datetime :completed_at
      t.timestamps
    end
    add_index :reminders, %i[workspace_id completed_at due_on]
  end
end
