class AddAvatarUrlToXConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :x_connections, :avatar_url, :string
  end
end
