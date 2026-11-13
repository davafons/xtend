# The connector and capture tokens become grants of the "Pasted token" client. Their digests carry over unchanged
# (Oauth::Token keeps the same HMAC), so Grok and the extension keep working without a new token.
class MoveWorkspaceTokensToOauth < ActiveRecord::Migration[8.1]
  def up
    now = connection.quote(Time.current)
    if select_value("SELECT 1 FROM workspaces WHERE mcp_token_digest IS NOT NULL OR capture_token_digest IS NOT NULL")
      execute <<~SQL
        INSERT INTO oauth_clients (client_id, name, redirect_uris, scopes, registered_via, created_at, updated_at)
        VALUES ('xtend-pasted-token', 'Pasted token', '[]', '["mcp","capture"]', 'first_party', #{now}, #{now})
      SQL
      client = select_value("SELECT id FROM oauth_clients WHERE client_id = 'xtend-pasted-token'")
      { "mcp" => "mcp", "capture" => "capture" }.each do |kind, scope|
        select_all("SELECT id, #{kind}_token_digest AS digest, #{kind}_token_created_at AS created, #{kind}_token_used_at AS used FROM workspaces WHERE #{kind}_token_digest IS NOT NULL").each do |row|
          user = select_value("SELECT id FROM users WHERE workspace_id = #{row["id"].to_i} ORDER BY id LIMIT 1")
          created = connection.quote(row["created"] || Time.current)
          execute <<~SQL
            INSERT INTO oauth_grants (workspace_id, user_id, oauth_client_id, scope, last_used_at, created_at, updated_at)
            VALUES (#{row["id"].to_i}, #{user ? user.to_i : "NULL"}, #{client.to_i}, '#{scope}', #{connection.quote(row["used"])}, #{created}, #{now})
          SQL
          grant = select_value("SELECT MAX(id) FROM oauth_grants")
          execute <<~SQL
            INSERT INTO oauth_tokens (oauth_grant_id, kind, token_digest, created_at, updated_at)
            VALUES (#{grant.to_i}, 'access', #{connection.quote(row["digest"])}, #{created}, #{now})
          SQL
        end
      end
    end

    %w[mcp capture].each do |kind|
      remove_index :workspaces, "#{kind}_token_digest"
      remove_column :workspaces, "#{kind}_token_digest", :string
      remove_column :workspaces, "#{kind}_token_created_at", :datetime
      remove_column :workspaces, "#{kind}_token_used_at", :datetime
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
