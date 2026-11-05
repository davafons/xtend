class Follow::Membership < ApplicationRecord
  include WorkspaceScoped
  belongs_to :person
  belongs_to :follow_snapshot, class_name: "Follow::Snapshot"
  validates :person_id, uniqueness: { scope: :follow_snapshot_id }
end
