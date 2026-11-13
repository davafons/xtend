# Clients are app-wide: first-party ones (the extension, pasted tokens) and ones AI clients register themselves.
# A grant links one client to one workspace for one scope; tokens and authorization codes store only digests.
class CreateOauth < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_clients do |t|
      t.string :client_id, null: false, index: { unique: true }
      t.string :name, null: false
      t.json :redirect_uris, null: false, default: []
      t.string :redirect_uri_pattern
      t.json :scopes, null: false, default: []
      t.string :registered_via, null: false, default: "first_party"
      t.timestamps
    end

    create_table :oauth_grants do |t|
      t.references :workspace, null: false, foreign_key: true, index: false
      t.references :user, foreign_key: true
      t.references :oauth_client, null: false, foreign_key: true
      t.string :scope, null: false
      t.string :user_agent
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
      t.index [ :workspace_id, :scope ]
    end

    create_table :oauth_tokens do |t|
      t.references :oauth_grant, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :token_digest, null: false, index: { unique: true }
      t.datetime :expires_at
      t.datetime :consumed_at
      t.timestamps
    end

    create_table :oauth_authorization_codes do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :oauth_client, null: false, foreign_key: true
      t.string :code_digest, null: false, index: { unique: true }
      t.string :redirect_uri, null: false
      t.string :code_challenge, null: false
      t.string :scope, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
  end
end
