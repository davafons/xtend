# Tagging people with AI so the owner can group them, such as followers by city, role, or topic. A connected
# assistant runs the tag_people and review_follows tasks (Mcp::Prompts); this holds what the app needs around them.
class AI::Classification
  BATCH = 40

  # The tag that marks an account unrelated to the owner's interests, so the follow review can put those first. It is
  # a tag like any other, added by AI or by hand.
  OFF_TOPIC = "off-topic"

  # Untagged followers first, when a follower list exists, then everyone else who is untagged.
  def self.batch
    followers = Follow::Graph.latest.follower_ids_query
    people = Person.untagged.where.not(x_id: nil)
    ordered = people.where(id: followers).order(:name).limit(BATCH).to_a
    ordered + people.where.not(id: ordered.map(&:id)).order(:name).limit(BATCH - ordered.size).to_a
  end
end
