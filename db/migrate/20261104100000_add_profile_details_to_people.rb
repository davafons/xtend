class AddProfileDetailsToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :banner_url, :string
    add_column :people, :location, :string
    add_column :people, :website_url, :string
    add_column :people, :followers_count, :integer
    add_column :people, :following_count, :integer
    add_column :people, :posts_count, :integer
    add_column :people, :joined_x_at, :datetime
    add_column :people, :profile_observed_at, :datetime
  end
end
