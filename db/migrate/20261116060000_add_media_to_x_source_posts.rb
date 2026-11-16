class AddMediaToXSourcePosts < ActiveRecord::Migration[8.1]
  def change
    add_column :x_source_posts, :media, :json
  end
end
