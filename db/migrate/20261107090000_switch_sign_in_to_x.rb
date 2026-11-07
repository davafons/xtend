# Sign-in moves to X. Users become an allow list of X handles, each pinned to an X user ID on first
# sign-in. Passwords, emails, the per-workspace X app form, and stored OAuth attempts go away: the X
# app now comes from the server environment, and the OAuth state lives in the signed session.
class SwitchSignInToX < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :x_handle, :string
    add_column :users, :x_user_id, :string

    # Keep existing owners: a workspace's connected X account becomes its user's pinned identity.
    execute <<~SQL
      UPDATE users SET
        x_handle = (SELECT lower(username) FROM x_connections WHERE x_connections.workspace_id = users.workspace_id),
        x_user_id = (SELECT x_user_id FROM x_connections WHERE x_connections.workspace_id = users.workspace_id)
    SQL
    # Users without a connected X account can't be matched. Their workspace data stays;
    # `bin/rails users:allow HANDLE=... WORKSPACE_ID=...` lets them back in.
    execute "DELETE FROM sessions WHERE user_id IN (SELECT id FROM users WHERE x_handle IS NULL)"
    execute "DELETE FROM users WHERE x_handle IS NULL"

    change_column_null :users, :x_handle, false
    add_index :users, :x_handle, unique: true
    add_index :users, :x_user_id, unique: true
    remove_index :users, :email_address
    remove_column :users, :email_address
    remove_column :users, :password_digest

    drop_table :x_client_configurations
    drop_table :x_authorizations
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
