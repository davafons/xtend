class FollowMembership < ApplicationRecord
  belongs_to :person
  belongs_to :follow_snapshot
  validates :person_id, uniqueness: { scope: :follow_snapshot_id }
end
