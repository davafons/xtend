# Who you follow and who follows you: the latest follow snapshot for each direction, corrected person by person
# by any newer relationship x.com showed the browser capture (a profile, a list, or your own follow or unfollow).
# A capture only corrects the people it saw; everyone else keeps the snapshot's answer.
class Follow::Graph
  attr_reader :following, :followers

  def self.latest
    new(Follow::Snapshot.latest("following"), Follow::Snapshot.latest("followers"))
  end

  def initialize(following, followers)
    @following = following
    @followers = followers
  end

  def complete?
    following&.completed_at.present? && followers&.completed_at.present?
  end

  # Person ids as a subquery, for scopes: `Person.where(id: graph.following_ids_query)`.
  def following_ids_query = current(following, :you_follow)
  def follower_ids_query = current(followers, :follows_you)

  def following?(person)
    following_ids.include?(person.id)
  end

  def follower?(person)
    follower_ids.include?(person.id)
  end

  def following_ids
    @following_ids ||= following_ids_query.pluck(:id).to_set
  end

  def follower_ids
    @follower_ids ||= follower_ids_query.pluck(:id).to_set
  end

  def state_for(person)
    outgoing = following?(person)
    incoming = follower?(person)
    return "Mutual" if outgoing && incoming
    if complete?
      return "You follow" if outgoing
      return "Follows you" if incoming
      return "Neither"
    end
    return "You follow · follow-back unknown" if outgoing
    return "Observed follower" if incoming
    "Unknown"
  end

  private

  def current(snapshot, flag)
    seen = "people.#{flag}_seen_at"
    observed = Person.where(flag => true)
    return observed.select(:id) unless snapshot
    listed = Person.where(id: snapshot.follow_memberships.select(:person_id))
      .where("NOT IFNULL(people.#{flag} = 0 AND #{seen} > ?, 0)", snapshot.observed_at)
    listed.or(observed.where("#{seen} > ?", snapshot.observed_at)).select(:id)
  end
end
