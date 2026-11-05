class DemoWorkspace
  def self.seed!
    raise "Demo data requires CRM_DEMO=1 and its separate database." unless Rails.configuration.x.demo
    return if Post.exists?

    ApplicationRecord.transaction do
      Workspace.current.update!(name: "Demo workspace", owner_x_id: "999")
      profiles = [
        [ "9001", "demo_maya", "Maya Chen", "Building developer tools for small teams. Cares about useful interfaces and shipping less software." ],
        [ "9002", "demo_alex", "Alex Rivera", "Independent Rails builder. Shares the messy middle of launching a small product." ],
        [ "9003", "demo_noor", "Noor Patel", "Making AI agents easier to evaluate. Experiments with workflows that keep humans in control." ],
        [ "9004", "demo_jules", "Jules Park", "Building a language-learning app around real conversations and everyday media." ],
        [ "9005", "demo_ellis", "Ellis Morgan", "Writes thoughtful notes on design systems and calm interfaces." ],
        [ "9006", "demo_robin", "Robin Bell", "Product updates and the occasional internet observation." ],
        [ "9007", "demo_sam", "Sam Vale", "An old follow from a different corner of the internet." ],
        [ "9008", "demo_leah", "Leah Tran", "Working on personal data tools and local search." ]
      ].map { |x_id, handle, name, description| Person.resolve_profile!(x_id: x_id, handle: handle, name: name, description: description) }
      profiles[0].create_pin!
      profiles[2].create_pin!
      profiles[0].update!(notes: "Fictional example note: met through a discussion about developer environments. Ask how the small-team rollout went.")
      profiles[4].create_follow_protection!

      messages = [
        [ 0, "I spent this week replacing three setup scripts with one command. The hard part wasn't the CLI. It was figuring out which decisions developers shouldn't have to make. What's the most useful thing you've removed from your onboarding?", "Developer tooling", "Connects with your work on local dev environments and reducing setup friction." ],
        [ 2, "We evaluate an agent's final answer, but barely look at whether it recovered from a bad tool call. I'm starting to think recovery is a better signal than a perfect first attempt. How are you testing this?", "Agent workflows", "A practical question about testing agents, not another model announcement." ],
        [ 1, "Shipped the smallest version of our expense app today. No analytics dashboard, no onboarding tour. Just create a group and split something. The scope cuts were uncomfortable and completely worth it.", "Shipping products", "A builder sharing concrete product tradeoffs you can relate to." ],
        [ 3, "Our dictionary search used to optimize for exact matches. Learners mostly arrive with half-remembered words. The next iteration is about making an imperfect query useful. Has anyone solved a similar discovery problem?", "Language tools", "Overlaps with Japanese search and dictionary work. There's a real product question here." ],
        [ 7, "A personal archive is only useful if you can find the thing you half remember. I'm trying a timeline plus local search, before adding any AI. What do you wish your own tools remembered?", "Local-first tools", "Relevant to personal data, local search, and context that stays useful over time." ]
      ]
      messages.each_with_index do |(author, body, topic, reason), index|
        Post.create!(person: profiles[author], x_id: (81000 + index).to_s, body: body, topic: topic, match_reason: reason, published_at: (index + 1).hours.ago, rank: 100 - index)
      end
      12.times do |index|
        person = profiles[index.even? ? 0 : 1]
        ReplyEvent.ingest_verified!(profile: { x_id: person.x_id, handle: person.handle, name: person.name }, x_id: (71000 + index).to_s, target_x_id: (61000 + index).to_s, direction: "outgoing", classification: "initial", source: "demo", occurred_at: Time.current.beginning_of_day + index.minutes, confirmed_at: Time.current)
      end
      [ profiles[0], profiles[2] ].each_with_index do |person, index|
        ReplyEvent.ingest_verified!(profile: { x_id: person.x_id, handle: person.handle, name: person.name }, x_id: (72000 + index).to_s, target_x_id: (62000 + index).to_s, direction: "incoming", classification: "continuation", source: "demo", occurred_at: 14.days.ago, confirmed_at: Time.current)
      end
      following = FollowSnapshot.create!(direction: "following", source: "demo", observed_at: Time.current, completed_at: Time.current)
      followers = FollowSnapshot.create!(direction: "followers", source: "demo", observed_at: Time.current, completed_at: Time.current)
      [ 0, 1, 3, 4, 5, 6 ].each { |index| following.follow_memberships.create!(person: profiles[index]) }
      [ 0, 2, 3 ].each { |index| followers.follow_memberships.create!(person: profiles[index]) }
    end
  end
end
