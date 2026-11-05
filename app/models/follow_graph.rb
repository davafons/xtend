class FollowGraph
  attr_reader :following, :followers

  def self.latest
    new(FollowSnapshot.latest("following"), FollowSnapshot.latest("followers"))
  end

  def initialize(following, followers)
    @following = following
    @followers = followers
  end

  def complete?
    following&.completed_at.present? && followers&.completed_at.present?
  end

  def following?(person)
    following_ids.include?(person.id)
  end

  def follower?(person)
    follower_ids.include?(person.id)
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

  def following_ids
    @following_ids ||= following ? following.person_ids.to_set : Set.new
  end

  def follower_ids
    @follower_ids ||= followers ? followers.person_ids.to_set : Set.new
  end
end
