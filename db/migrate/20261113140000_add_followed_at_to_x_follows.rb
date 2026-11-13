class AddFollowedAtToXFollows < ActiveRecord::Migration[8.1]
  def change
    add_column :x_follows, :followed_at, :datetime
  end
end
