class Follow::Review < ApplicationRecord
  include WorkspaceScoped
  belongs_to :person
  validates :decision, inclusion: { in: %w[keep defer reported_unfollow unfollowed] }
  validates :reviewed_on, presence: true
  validates :person_id, uniqueness: { scope: :reviewed_on }

  # Settles every reported unfollow that the evidence can decide, so none stays unverified for long:
  # - confirmed (becomes "unfollowed") when a complete following list or x.com shows you no longer follow them;
  # - refuted (the report is removed, so they return to review) when a complete list saved after the report, or
  #   x.com after it, still shows you following them.
  # A report newer than every piece of evidence waits for the next Following scroll or x.com sighting.
  def self.settle_reported!
    list = Follow::Snapshot.latest_complete("following")
    listed = list ? list.follow_memberships.pluck(:person_id).to_set : Set.new
    settled = { confirmed: 0, refuted: 0 }
    where(decision: "reported_unfollow").includes(:person).find_each do |review|
      person = review.person
      reported = review.updated_at
      seen = person.you_follow_seen_at if person.you_follow_seen_at && person.you_follow_seen_at > reported
      following = if seen then person.you_follow
      elsif list && list.observed_at > reported then listed.include?(person.id)
      elsif list && !listed.include?(person.id) then false
      end
      next if following.nil?
      if following
        review.destroy!
        settled[:refuted] += 1
      else
        review.update!(decision: "unfollowed")
        settled[:confirmed] += 1
      end
    end
    settled
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
