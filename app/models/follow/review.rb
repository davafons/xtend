class Follow::Review < ApplicationRecord
  belongs_to :person
  validates :decision, inclusion: { in: %w[keep defer reported_unfollow] }
  validates :reviewed_on, presence: true
  validates :person_id, uniqueness: { scope: :reviewed_on }

  def self.record!(person, decision)
    transaction do
      person.create_follow_protection! if decision == "keep" && !person.follow_protection
      review = find_or_initialize_by(person: person, reviewed_on: Date.current)
      review.update!(decision: decision)
      review
    end
  end
end
