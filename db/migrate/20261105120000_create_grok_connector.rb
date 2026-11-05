class CreateGrokConnector < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :source, :string, null: false, default: "x_api"
    add_column :posts, :grok_run_id, :string

    add_column :workspaces, :mcp_token_digest, :string
    add_column :workspaces, :mcp_token_created_at, :datetime
    add_column :workspaces, :mcp_token_used_at, :datetime
    add_column :workspaces, :mcp_share_notes, :boolean, null: false, default: false
    add_column :workspaces, :mcp_share_dms, :boolean, null: false, default: false

    create_table :grok_proposals do |t|
      t.references :person, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :status, null: false, default: "pending"
      t.json :payload, null: false, default: {}
      t.string :run_id
      t.string :via, null: false
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :grok_proposals, [:person_id, :kind, :status]
  end
end
