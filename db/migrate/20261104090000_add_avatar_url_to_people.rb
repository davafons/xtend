class AddAvatarUrlToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :avatar_url, :string
  end
end
