# The latest follow relationship x.com showed for a person, in each direction. Newer than the latest follow
# snapshot, it overrides that snapshot's answer for this one person.
class AddObservedRelationshipToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :you_follow, :boolean
    add_column :people, :you_follow_seen_at, :datetime
    add_column :people, :follows_you, :boolean
    add_column :people, :follows_you_seen_at, :datetime
  end
end
