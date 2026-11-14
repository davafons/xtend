# Xtend's tasks for a connected AI, served as MCP prompts (a client may offer them as commands) and through the
# get_task tool for clients without prompt support. Each prompt says which tools to read, what to judge, and what
# to write back; the data comes from the tools, so nothing is pasted and every task works from current data.
class Mcp::Prompts
  COMMON = <<~TEXT.squish
    Use the xtend tools for all data instead of asking the owner to paste anything. Before writing, call list_ai_changes to
    skip what an AI already did. Base every judgment on the evidence the tools return or on public posts you can open,
    say what it rests on, and leave out what you can't support. Writes stay inside Xtend; the owner replies, follows, and
    unfollows himself on X. Finish with a short summary of what you found and what you changed.
  TEXT

  TASKS = {
    "tag_people" => {
      title: "Tag people",
      description: "Tag untagged people by place, role, and topic so you can group them.",
      text: <<~TEXT
        Tag the people in Xtend who have no tags yet.
        1. get_owner_profile for the existing tag vocabulary; reuse those tags where they fit.
        2. list_people with filter "untagged" (page through with cursor, up to 100 people).
        3. Give each person 1 to 5 short lowercase tags: where they are based (only if their profile says so), what they do
           (such as "indie hacker", "ios dev", "founder"), and their main topics. Look at their public profile and recent posts.
        4. add_tags in batches of up to 50, with a short reason quoting the evidence.
      TEXT
    },
    "review_follows" => {
      title: "Review who you follow",
      description: "Judge which accounts in your follow review fit your interests, and tag the ones that don't.",
      text: <<~TEXT
        Help the owner decide who to keep following.
        1. get_follow_review_batch (reason inactive, then strangers and quiet if he asks) for the accounts to review and his interests.
        2. For each account, judge from its bio and recent posts, and its public posts on X if needed, whether it relates to anything
           in his interests. An account that posts about them even occasionally fits.
        3. add_tags: give accounts that don't fit the off-topic tag the batch names, and give every account its place, role, and
           topic tags too, so the review can group them.
        4. Summarize: which look safe to drop and why, and which to keep despite being quiet. Never call someone inactive when
           their last post is unknown. The owner makes the decisions on the Follow review page.
      TEXT
    },
    "research_person" => {
      title: "Research a person",
      description: "Look someone up, write a recap, note what's worth knowing, and suggest a reason to reach out.",
      arguments: [ { name: "handle", description: "Their X handle, without @.", required: true } ],
      text: <<~TEXT
        Research @%{handle} for the owner.
        1. get_person_context and get_interaction_history for what Xtend knows and what passed between them.
        2. Read their public profile and recent posts on X.
        3. save_recap: who they are and what they're working on now, with evidence_urls to their posts.
        4. fill_profile_facts for public facts Xtend is missing, and add_tags for place, role, and topics.
        5. If there's a natural next step (a launch to ask about, a question they asked), add_note with it, and set_reminder
           for when it makes sense. Don't set a reminder without a concrete reason.
      TEXT
    },
    "weekly_review" => {
      title: "Weekly review",
      description: "Review your week, explain what worked, and set up next week's follow-ups.",
      text: <<~TEXT
        Review the owner's week on X.
        1. get_week_review (weeks_ago 0, and 1 to compare) and get_x_analytics with period 30d.
        2. Explain what worked and what didn't: which replies brought profile visits or follows, to whom, and when; how the week
           compares with the one before. Use only the numbers returned, and say when coverage is partial.
        3. For people who've gone quiet or have replies waiting, get_person_context, then set_reminder for the ones worth
           reconnecting with, with a concrete reason, spread over the next week.
        4. Suggest 3 changes for next week (who to reply to, when, what to post), grounded in the numbers.
      TEXT
    },
    "what_works" => {
      title: "What works",
      description: "Find which replies, posts, accounts, and hours bring you reach and followers.",
      text: <<~TEXT
        Work out what brings the owner reach and new followers.
        1. get_x_analytics with period 90d (top posts, best replies, replies by account size and hour) and get_post_performance.
        2. Compare: replies by account size and time (busy hours), his best replies and posts and what they have in common
           (topic, format, length, a question, a number, media), and who he reached.
        3. For the people his best replies went to, add_tags so they can be found again, and add_note on what landed with them.
        4. Answer with concrete patterns, each with its numbers and how many examples it rests on. Say "not enough data" where
           there are fewer than 3 examples.
      TEXT
    },
    "post_ideas" => {
      title: "Post ideas",
      description: "Suggest posts for this week from what works for you and what your network is talking about.",
      text: <<~TEXT
        Suggest 10 posts the owner could write this week.
        1. get_owner_profile for his interests, list_post_drafts to avoid repeats, get_post_performance and get_x_analytics for
           what works, and list_network_posts (period 7d, sort top) for what his network is talking about.
        2. Prefer concrete experiences, lessons, numbers, and questions over hot takes.
        3. save_post_idea for each, with the angle and why it could work in notes and the network post that inspired it as
           inspiration_url. Write a first draft only if he asks.
      TEXT
    },
    "find_reply_targets" => {
      title: "Find reply targets",
      description: "Find fresh public posts worth a reply and add them to Outreach.",
      text: <<~TEXT
        Find posts the owner could reply to today.
        1. get_session_state and list_known_posts to skip what he has already seen or answered, get_owner_profile for his
           interests and discovery filters, and get_x_analytics for the account sizes his replies pay off with.
        2. Search public X for English posts from the last two days with few replies where he could add something useful.
        3. propose_candidate_posts with real URLs, the text as observed, and one concrete reason each.
      TEXT
    }
  }.freeze

  def self.names = TASKS.keys

  def self.definitions
    TASKS.map do |name, task|
      { name: name, title: task[:title], description: task[:description], arguments: task[:arguments] }.compact
    end
  end

  # { description:, messages: } for prompts/get; raises ArgumentError for an unknown task or missing argument.
  def self.get(name, arguments = {})
    task = TASKS[name] or raise ArgumentError, "Unknown task. Use one of #{names.join(', ')}."
    values = Array(task[:arguments]).to_h do |argument|
      value = arguments.to_h[argument[:name]].to_s.delete_prefix("@").strip
      raise ArgumentError, "#{argument[:name]} is required." if argument[:required] && value.empty?
      [ argument[:name].to_sym, value.first(50) ]
    end
    { description: task[:description], messages: [ { role: "user", content: { type: "text", text: "#{format(task[:text], values)}\n#{COMMON}" } } ] }
  end
end
