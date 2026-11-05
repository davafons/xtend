class CreateFollowReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :follow_reviews do |t|
      t.references :person, null: false, foreign_key: true
      t.string :decision, null: false
      t.date :reviewed_on, null: false
      t.timestamps
    end
    add_index :follow_reviews, [ :person_id, :reviewed_on ], unique: true
  end
end
