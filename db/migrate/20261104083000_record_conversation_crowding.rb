class RecordConversationCrowding < ActiveRecord::Migration[8.1]
  def change
    add_column :x_source_posts, :reply_count, :integer
    add_column :posts, :reply_count, :integer
  end
end
