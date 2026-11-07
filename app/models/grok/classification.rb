# Asks Grok to tag people so the owner can group them, such as followers by city, role, or topic.
# The prompt carries a bounded batch of untagged people; results come back as tag proposals.
class Grok::Classification
  BATCH = 40

  # Untagged followers first, when a follower list exists, then everyone else who is untagged.
  def self.batch
    followers = Follow::Graph.latest.follower_ids_query
    people = Person.untagged.where.not(x_id: nil)
    ordered = people.where(id: followers).order(:name).limit(BATCH).to_a
    ordered + people.where.not(id: ordered.map(&:id)).order(:name).limit(BATCH - ordered.size).to_a
  end

  def self.prompt(people = batch)
    vocabulary = Tag.by_use.limit(60).map(&:name)
    rows = people.map do |person|
      { handle: person.handle, name: person.name, bio: person.description&.squish&.first(200), location: person.location }.compact
    end
    <<~PROMPT
      Tag these X accounts so I can group the people I follow and who follow me.
      Give each person 1 to 5 short lowercase tags: where they are based (a city or country, only if their profile says so), what they do (such as "indie hacker", "ios dev", "designer", "founder"), and their main topics (such as "rails", "ai agents", "japanese learning").
      #{vocabulary.any? ? "Reuse these existing tags where they fit: #{vocabulary.join(', ')}." : "Keep tags consistent across people so they group well."}
      Base tags only on public profile information and public posts. Skip anyone you cannot find, and do not guess a location.
      If the twitter-crm MCP connector is available, call list_people with filter "untagged" and then propose_tags instead of answering in text.
      Otherwise end your answer with one JSON code block in exactly this shape, so I can paste it into my CRM:
      {"format": "#{Grok::Intake::FORMAT}", "tags": [{"handle": "handle", "tags": ["tokyo", "indie hacker"], "reason": "Bio says: Tokyo indie hacker"}]}
      People:
      #{rows.map(&:to_json).join("\n")}
      Do not post, message, follow, or unfollow anyone.
    PROMPT
  end
end
