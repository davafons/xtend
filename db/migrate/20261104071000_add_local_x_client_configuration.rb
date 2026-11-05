class AddLocalXClientConfiguration < ActiveRecord::Migration[8.1]
  def change
    create_table :x_client_configurations do |t|
      t.text :settings_ciphertext, null: false
      t.timestamps
    end
    add_index :x_client_configurations, "(1)", unique: true, name: "index_single_x_client_configuration"
  end
end
