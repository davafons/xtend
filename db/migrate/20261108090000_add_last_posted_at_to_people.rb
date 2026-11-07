class AddLastPostedAtToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :last_posted_at, :datetime
  end
end
