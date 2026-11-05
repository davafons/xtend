class AddXConnection < ActiveRecord::Migration[8.1]
  def change
    create_table :x_connections do |t|
      t.string :x_user_id, null: false
      t.string :username, null: false
      t.text :token_ciphertext, null: false
      t.text :granted_scopes, null: false
      t.datetime :expires_at, null: false
      t.datetime :identity_checked_at, null: false
      t.timestamps
    end
    add_index :x_connections, "(1)", unique: true, name: "index_single_owner_x_connection"
    create_table :x_authorizations do |t|
      t.string :state_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :x_authorizations, :state_digest, unique: true
  end
end
