class Follow::Review < ApplicationRecord
  include WorkspaceScoped
  belongs_to :person
  validates :decision, inclusion: { in: %w[keep defer reported_unfollow unfollowed] }
  validates :reviewed_on, presence: true
  validates :person_id, uniqueness: { scope: :reviewed_on }

  # A complete following list settles reported unfollows: anyone not on it is no longer followed.
  def self.confirm_unfollows!(list)
    return 0 unless list.direction == "following" && list.completed_at
    where(decision: "reported_unfollow").where.not(person_id: list.follow_memberships.select(:person_id))
      .update_all(decision: "unfollowed", updated_at: Time.current)
  end

  def self.record!(person, decision)
    transaction do
      person.create_follow_protection! if decision == "keep" && !person.follow_protection
      review = find_or_initialize_by(person: person, reviewed_on: Date.current)
      review.update!(decision: decision)
      review
    end
  end
end
