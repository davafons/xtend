class CreateGrowthPlan < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :growth_goal, :integer
    add_column :workspaces, :growth_started_on, :date
    add_column :workspaces, :growth_start_followers, :integer

    # Checklist items the owner ticks by hand, per plan week (setup items use week 1).
    create_table :outreach_growth_checks do |t|
      t.references :workspace, null: false, foreign_key: true
      t.integer :week, null: false
      t.string :key, null: false
      t.timestamps
    end
    add_index :outreach_growth_checks, [ :workspace_id, :week, :key ], unique: true
  end
end
