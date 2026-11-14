class AddPostCountsToXArchiveImports < ActiveRecord::Migration[8.1]
  def change
    add_column :x_archive_imports, :posts_count, :integer, default: 0, null: false
    add_column :x_archive_imports, :replies_count, :integer, default: 0, null: false
    add_column :x_archive_imports, :people_count, :integer, default: 0, null: false
    add_column :x_archive_imports, :status, :string, default: "completed", null: false
    add_column :x_archive_imports, :message, :text
  end
end
