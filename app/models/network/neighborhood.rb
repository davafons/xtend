# One person's place in the network: who else in your CRM they interact with, and which of your people follow
# them or are followed by them on lists the capture saw. The owner is left out; the relationship card covers that.
class Network::Neighborhood
  LIMIT = 8

  def initialize(person)
    @x_id = person.x_id.to_s
    @owner = Current.workspace.owner_x_id.to_s
  end

  def empty?
    @x_id.blank? || (partners.empty? && followed_by.empty? && follows.empty?)
  end

  # [[person, { "reply" => 3, ... }], ...] busiest first.
  def partners
    @partners ||= begin
      counts = Hash.new { |hash, key| hash[key] = Hash.new(0) }
      X::Interaction.where(source_x_id: @x_id).where.not(target_x_id: @owner).group(:target_x_id, :kind).count.each { |(other, kind), count| counts[other][kind] += count }
      X::Interaction.where(target_x_id: @x_id).where.not(source_x_id: @owner).group(:source_x_id, :kind).count.each { |(other, kind), count| counts[other][kind] += count }
      people = Person.where(x_id: counts.keys).index_by(&:x_id)
      counts.filter_map { |other, kinds| [ people[other], kinds ] if people[other] }.sort_by { |_, kinds| -kinds.values.sum }.first(LIMIT)
    end
  end

  def followed_by
    @followed_by ||= Person.where(x_id: X::FollowEdge.where(followed_x_id: @x_id).where.not(follower_x_id: @owner).select(:follower_x_id)).limit(LIMIT).to_a
  end

  def follows
    @follows ||= Person.where(x_id: X::FollowEdge.where(follower_x_id: @x_id).where.not(followed_x_id: @owner).select(:followed_x_id)).limit(LIMIT).to_a
  end

  def saved_posts
    @saved_posts ||= @x_id.present? ? X::SourcePost.where(author_x_id: @x_id, repost: false).count : 0
  end
end
