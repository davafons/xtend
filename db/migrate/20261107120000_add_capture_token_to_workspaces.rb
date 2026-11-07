class AddCaptureTokenToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :capture_token_digest, :string
    add_column :workspaces, :capture_token_created_at, :datetime
    add_column :workspaces, :capture_token_used_at, :datetime
    add_index :workspaces, :capture_token_digest, unique: true
  end
end
