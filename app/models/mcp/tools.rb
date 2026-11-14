# Tools that any MCP client (Grok Bot, Claude, ChatGPT, ...) can call. Reads are bounded and scoped by the owner's sharing
# choices. Writes go through AI::Intake (tags, recaps, profile facts, notes, reminders), which applies them at once
# with an undo when the owner lets AI apply changes and stages them for review otherwise, or save post drafts and
# unverified reply targets. Every write stays inside Xtend: no tool posts, follows, messages, or runs paid X reads.
class Mcp::Tools
  class Invalid < StandardError; end

  PERSON_REF = {
    person_id: { type: "integer", description: "Xtend person ID from list_people." },
    handle: { type: "string", description: "X handle without @. Used when person_id is absent." }
  }.freeze
  CANDIDATE = {
    type: "object",
    required: %w[url text published_at],
    properties: {
      url: { type: "string", description: "Real public post URL, e.g. https://x.com/handle/status/123." },
      author_handle: { type: "string" }, author_name: { type: "string" }, author_bio: { type: "string" },
      author_followers_count: { type: "integer" },
      text: { type: "string", description: "Post text as observed, up to 1,000 characters." },
      published_at: { type: "string", description: "ISO-8601 post time as observed." },
      reply_count: { type: "integer" }, language: { type: "string", description: "Defaults to en." },
      match_reason: { type: "string", description: "One concrete reason the owner could add a useful reply." }
    }
  }.freeze

  MAX_VARIATIONS = 10
  APPLY_NOTE = "Applies at once with an undo when the owner lets AI apply changes, otherwise waits for their review; the result says which."

  DEFINITIONS = [
    { name: "get_owner_profile", title: "Owner interests and rules",
      description: "The owner's interests, the daily reply goal, discovery filters, and which private categories they share.",
      inputSchema: { type: "object", properties: {} }, annotations: { readOnlyHint: true } },
    { name: "get_session_state", title: "Today's session",
      description: "Progress toward 20 distinct new reply targets, plus post IDs already replied to. Use it to avoid duplicates.",
      inputSchema: { type: "object", properties: {} }, annotations: { readOnlyHint: true } },
    { name: "list_people", title: "List people",
      description: "Bounded list of people in Xtend with follow state, reply state, tags, pins, keeps, and last observed interaction.",
      inputSchema: { type: "object", properties: {
        filter: { type: "string", enum: %w[all pinned kept mutual you_follow follows_you replied untagged] },
        tag: { type: "string", description: "Only people with this tag." },
        query: { type: "string", description: "Match name, handle, or bio." },
        limit: { type: "integer", minimum: 1, maximum: 50 }, cursor: { type: "string" } } },
      annotations: { readOnlyHint: true } },
    { name: "get_person_context", title: "Person context",
      description: "One person's profile, relationship facts, recent collected posts, accepted recap, and notes when shared.",
      inputSchema: { type: "object", properties: PERSON_REF }, annotations: { readOnlyHint: true } },
    { name: "get_interaction_history", title: "Interaction history",
      description: "Collected replies, likes, bookmarks, and DM metadata (when shared) with one person, newest first, plus coverage limits.",
      inputSchema: { type: "object", properties: PERSON_REF.merge(limit: { type: "integer", minimum: 1, maximum: 50 }) },
      annotations: { readOnlyHint: true } },
    { name: "list_pending_proposals", title: "Proposals awaiting review",
      description: "Tags, recaps, and profile facts staged for the owner that they have not accepted or dismissed yet, plus unverified reply targets still on their Outreach page. Check it before proposing so you add to the queue instead of repeating it.",
      inputSchema: { type: "object", properties: {
        kind: { type: "string", enum: AI::Proposal::KINDS + %w[posts], description: "Only one kind. Defaults to all." },
        limit: { type: "integer", minimum: 1, maximum: 50 } } },
      annotations: { readOnlyHint: true } },
    { name: "list_known_posts", title: "Known post IDs",
      description: "Post IDs already in Xtend within a window, so proposals skip duplicates.",
      inputSchema: { type: "object", properties: { days: { type: "integer", minimum: 1, maximum: 30 } } },
      annotations: { readOnlyHint: true } },
    { name: "propose_candidate_posts", title: "Propose reply targets",
      description: "Stage up to 20 public posts as unverified reply candidates on the owner's Outreach page. Does not reply or mark anything sent.",
      inputSchema: { type: "object", required: %w[posts], properties: {
        run_id: { type: "string" }, posts: { type: "array", maxItems: 20, items: CANDIDATE } } },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true } },
    { name: "fill_profile_facts", title: "Fill profile facts",
      description: "Add public profile facts for an existing person. They only fill fields Xtend does not have; X-collected data and the owner's edits always win. #{APPLY_NOTE}",
      inputSchema: { type: "object", properties: PERSON_REF.merge(
        name: { type: "string" }, description: { type: "string" }, location: { type: "string" },
        website_url: { type: "string" }, followers_count: { type: "integer" }, following_count: { type: "integer" },
        observed_at: { type: "string" }, run_id: { type: "string" }) },
      annotations: { readOnlyHint: false, destructiveHint: false } },
    { name: "save_recap", title: "Save a person recap",
      description: "Save a short evidence-linked summary of who someone is and what they are working on. It shows on their page as AI research. #{APPLY_NOTE}",
      inputSchema: { type: "object", required: %w[summary], properties: PERSON_REF.merge(
        summary: { type: "string", maxLength: 1500 },
        evidence_urls: { type: "array", maxItems: 10, items: { type: "string" } }, run_id: { type: "string" }) },
      annotations: { readOnlyHint: false, destructiveHint: false } },
    { name: "add_tags", title: "Add tags",
      description: "Add tags to up to 50 existing people, such as a city, role, or topic, so the owner can group them. Reuse tags from get_owner_profile where they fit. Existing tags are never removed. #{APPLY_NOTE}",
      inputSchema: { type: "object", required: %w[assignments], properties: {
        run_id: { type: "string" },
        assignments: { type: "array", maxItems: 50, items: { type: "object", required: %w[tags], properties: PERSON_REF.merge(
          tags: { type: "array", maxItems: 8, items: { type: "string", maxLength: 40 } },
          reason: { type: "string", description: "Short public evidence for the tags, such as the bio or recent posts." }) } } } },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true } },
    { name: "add_note", title: "Add a note",
      description: "Add a short note to a person's private notes in Xtend, such as what they are building or what to ask next time. It is marked as yours and placed below the owner's own notes, which never change. #{APPLY_NOTE}",
      inputSchema: { type: "object", required: %w[text], properties: PERSON_REF.merge(
        text: { type: "string", maxLength: AI::Intake::NOTE_LENGTH }, run_id: { type: "string" }) },
      annotations: { readOnlyHint: false, destructiveHint: false } },
    { name: "set_reminder", title: "Set a reminder",
      description: "Remind the owner to do something about a person on a day, such as following up on a launch. It shows on Outreach and the weekly review when due. It never sends anything. #{APPLY_NOTE}",
      inputSchema: { type: "object", required: %w[reason due_on], properties: PERSON_REF.merge(
        reason: { type: "string", maxLength: Reminder::REASON_LENGTH }, due_on: { type: "string", description: "YYYY-MM-DD, today to a year ahead." },
        run_id: { type: "string" }) },
      annotations: { readOnlyHint: false, destructiveHint: false } },
    { name: "list_ai_changes", title: "Changes AI made",
      description: "Recent tags, notes, reminders, recaps, and profile facts any AI applied or proposed, with their status (applied, accepted, pending, dismissed, undone). Check it before writing so you don't repeat work, and use the ids with undo_ai_change.",
      inputSchema: { type: "object", properties: {
        status: { type: "string", enum: AI::Proposal::STATUSES }, limit: { type: "integer", minimum: 1, maximum: 50 } } },
      annotations: { readOnlyHint: true } },
    { name: "undo_ai_change", title: "Undo an AI change",
      description: "Reverse a change an AI applied, by id from list_ai_changes, such as a wrong tag. Only the change itself is reversed; anything the owner edited since stays.",
      inputSchema: { type: "object", required: %w[id], properties: { id: { type: "integer" } } },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true } },
    { name: "get_follow_review_batch", title: "Follow review batch",
      description: "The next accounts the owner follows that cleanup suggests reviewing (inactive, never interacted, or quiet), with bio, follow state, tags, last interaction, and their latest collected posts. Use it to judge which fit their interests; mark ones that don't with the off-topic tag via add_tags. The owner decides who to unfollow, on X.",
      inputSchema: { type: "object", properties: {
        reason: { type: "string", enum: Follow::Cleanup::REASONS.keys, description: "Defaults to inactive." },
        limit: { type: "integer", minimum: 1, maximum: 50 } } },
      annotations: { readOnlyHint: true } },
    { name: "get_x_analytics", title: "X analytics",
      description: "X's own analytics as the extension saved them from x.com: daily totals (impressions, profile visits, follows, engagements), what the owner's replies brought by the size of the account they answered, their best replies and posts, their audience's busy hours of the week, and who they reached (followers vs not, countries). Use it to find what works.",
      inputSchema: { type: "object", properties: {
        period: { type: "string", enum: Network::Activity::PERIODS.keys, description: "Defaults to 30d." } } },
      annotations: { readOnlyHint: true } },
    { name: "get_week_review", title: "Week in review",
      description: "One week: replies sent, new targets, answers seen, replies to the owner, X analytics totals, follower changes, best reply and post, and what's next (replies waiting, reminders due, people gone quiet).",
      inputSchema: { type: "object", properties: {
        weeks_ago: { type: "integer", minimum: 0, maximum: Network::Week::MAX_WEEKS_AGO, description: "0 (default) is the seven days ending today." } } },
      annotations: { readOnlyHint: true } },
    { name: "get_growth_plan", title: "Growth plan",
      description: "The owner's growth plan: follower goal, start, this week's follower and profile-visit checkpoints against what Xtend saw, the week's checklist (ticked from data or by the owner), and their circle (people tagged circle) with who they replied to this week. Use it in weekly reviews to judge progress against the plan; tag new circle people with add_tags.",
      inputSchema: { type: "object", properties: {
        week: { type: "integer", minimum: 1, maximum: Outreach::Growth::WEEKS, description: "Plan week; default is the current one." } } },
      annotations: { readOnlyHint: true } },
    { name: "get_task", title: "Task instructions",
      description: "Step-by-step instructions for one of Xtend's tasks, for clients without MCP prompts: #{Mcp::Prompts.names.join(', ')}. Follow them with the other tools.",
      inputSchema: { type: "object", required: %w[task], properties: {
        task: { type: "string", enum: Mcp::Prompts.names }, handle: { type: "string", description: "For research_person." } } },
      annotations: { readOnlyHint: true } },
    { name: "list_network_posts", title: "Network posts",
      description: "Posts from the owner's network that they collected or scrolled past on x.com, with the counts last seen (likes, reposts, replies, quotes, bookmarks, views). Use them as references for style and topics. Counts are not live, and coverage is only what was captured.",
      inputSchema: { type: "object", properties: PERSON_REF.merge(
        who: { type: "string", enum: Network::Timeline::WHO.keys, description: "network (default): The owner's people and the owner; seen: everything they were shown." },
        kind: { type: "string", enum: Network::Timeline::KINDS.keys, description: "Defaults to posts (no replies)." },
        sort: { type: "string", enum: Network::Timeline::SORTS.keys },
        period: { type: "string", enum: Network::Timeline::PERIODS.keys, description: "Defaults to 30d." },
        tag: { type: "string" }, query: { type: "string", description: "Text the post contains." },
        with_media: { type: "boolean" }, limit: { type: "integer", minimum: 1, maximum: 40 }) },
      annotations: { readOnlyHint: true } },
    { name: "get_network", title: "Network connections",
      description: "Who interacts with whom among the owner's people (replies, quotes, reposts, mentions, likes) and captured follow edges. With a person, their connections; without, the most connected people, the busiest pairs, and outside accounts several of their people talk to. A missing connection is not proof of none.",
      inputSchema: { type: "object", properties: PERSON_REF.merge(
        period: { type: "string", enum: Network::Graph::PERIODS.keys, description: "Defaults to 90d." },
        tag: { type: "string" }) },
      annotations: { readOnlyHint: true } },
    { name: "list_post_drafts", title: "List post drafts",
      description: "The owner's saved ideas and drafts for their own posts, newest first, with their alternative versions. Use draft IDs with add_post_variations.",
      inputSchema: { type: "object", properties: {
        stage: { type: "string", enum: Draft::STATUSES.keys, description: "Defaults to every stage except posted." },
        limit: { type: "integer", minimum: 1, maximum: 25 } } },
      annotations: { readOnlyHint: true } },
    { name: "get_post_performance", title: "How the owner's posts did",
      description: "Counts the capture last saw on the owner's own top-level posts: medians by format and the posts that went furthest. Only posts whose counts were seen at least two days after posting are compared. Use it to ground post ideas in what worked; it is not a complete analytics export.",
      inputSchema: { type: "object", properties: {
        days: { type: "integer", minimum: 7, maximum: 365, description: "How far back to look. Defaults to 90." } } },
      annotations: { readOnlyHint: true } },
    { name: "save_post_idea", title: "Save a post idea",
      description: "Save an idea for one of the owner's own posts in Compose, optionally with variations. The first text becomes the main draft and the rest are kept as alternatives. Separate posts in a thread with a line containing only ---. Saving never posts anything.",
      inputSchema: { type: "object", required: %w[texts], properties: {
        texts: { type: "array", minItems: 1, maxItems: MAX_VARIATIONS, items: { type: "string", maxLength: 5000 } },
        topic: { type: "string", maxLength: 120 },
        notes: { type: "string", maxLength: 2000, description: "Angle, sources, or why it could work. Never posted." },
        variation_note: { type: "string", maxLength: 200, description: "What the variations try, such as different hooks." },
        inspiration_url: { type: "string", description: "An x.com post that inspired the idea." },
        stage: { type: "string", enum: %w[idea drafting], description: "Defaults to idea." } } },
      annotations: { readOnlyHint: false, destructiveHint: false } },
    { name: "add_post_variations", title: "Add post variations",
      description: "Add alternative versions to an existing draft from list_post_drafts or save_post_idea. The main text is left unchanged; the owner chooses which version to use.",
      inputSchema: { type: "object", required: %w[draft_id texts], properties: {
        draft_id: { type: "integer" },
        texts: { type: "array", minItems: 1, maxItems: MAX_VARIATIONS, items: { type: "string", maxLength: 5000 } },
        note: { type: "string", maxLength: 200, description: "What these variations try." } } },
      annotations: { readOnlyHint: false, destructiveHint: false } }
  ].freeze

  def self.definitions = DEFINITIONS
  def self.names = DEFINITIONS.map { |tool| tool[:name] }

  def initialize
    @workspace = Current.workspace
    @demo = Rails.configuration.x.demo
  end

  def get_owner_profile(_args)
    { demo: @demo, handle: X::Connection.current&.username, interests: @workspace.interests,
      session_goal: "Replies on #{Outreach::Session::TARGET} distinct new target posts per session. Follow-ups in existing exchanges do not count.",
      discovery_filters: ["English only", "Posted in the last 7 days", "At most 50 replies", "No crypto, airdrops, engagement bait, follow-for-follow, or pure promotion", "No automated accounts"],
      tags: Tag.by_use.limit(200).map { |tag| { name: tag.name, people: tag.people_count } },
      shared_categories: { notes: @workspace.mcp_share_notes, dm_metadata: @workspace.mcp_share_dms },
      rules: "Reading or proposing never sends anything. The owner replies manually on X." }
  end

  def get_session_state(_args)
    session = Outreach::Session.current
    { demo: @demo, target: Outreach::Session::TARGET, progress: session.progress,
      remaining: [Outreach::Session::TARGET - session.progress, 0].max,
      queue: { available: Outreach::Candidate.opportunities.count, unverified_from_ai: Outreach::Candidate.opportunities.where(source: "ai").count },
      replied_post_ids: ReplyEvent.where(direction: "outgoing").order(occurred_at: :desc).limit(200).pluck(:target_x_id) }
  end

  def list_people(args)
    limit = bounded(args["limit"], 25, 50)
    offset = Integer(args["cursor"].presence || 0, exception: false)
    raise Invalid, "cursor must come from a previous list_people result." unless offset&.>=(0)
    graph = Follow::Graph.latest
    people = Person.order(:name, :id)
    if args["query"].present?
      term = "%#{Person.sanitize_sql_like(args['query'].to_s.first(100))}%"
      people = people.where("name LIKE ? OR handle LIKE ? OR description LIKE ?", term, term, term)
    end
    filter = args["filter"].presence || "all"
    following = graph.following_ids_query
    followers = graph.follower_ids_query
    # Follow filters need complete checks of both lists, as on the People page.
    people = people.none if %w[mutual you_follow follows_you].include?(filter) && !graph.complete?
    people = case filter
    when "all" then people
    when "pinned" then people.pinned
    when "kept" then people.where(id: Follow::Protection.select(:person_id))
    when "mutual" then people.where(id: following).where(id: followers)
    when "you_follow" then people.where(id: following)
    when "follows_you" then people.where(id: followers)
    when "replied" then people.where(id: ReplyEvent.select(:person_id))
    when "untagged" then people.untagged
    else raise Invalid, "Unknown filter."
    end
    people = people.tagged(args["tag"].to_s) if args["tag"].present?
    page = people.includes(:pin, :follow_protection, :reply_events, :tags).offset(offset).limit(limit + 1).to_a
    more = page.size > limit
    page = page.first(limit)
    interactions = Person::Interactions.index(page)
    { demo: @demo, follow_data: graph.complete? ? "complete checks" : "incomplete; follow states may be unknown",
      people: page.map { |person| person_summary(person, graph, interactions.fetch(person.id)) },
      next_cursor: more ? (offset + limit).to_s : nil }
  end

  def get_person_context(args)
    person = find_person!(args)
    graph = Follow::Graph.latest
    recent = person.x_id ? X::SourcePost.where(author_x_id: person.x_id, repost: false).order(published_at: :desc).limit(5) : []
    recap = person.ai_proposals.latest_recap
    context = person_summary(person, graph, person.interactions).merge(
      profile_url: person.profile_url, location: person.location, website_url: person.website_url,
      followers_count: person.followers_count, following_count: person.following_count,
      profile_source: person.x_id ? "x_api" : "ai_research_unverified",
      outgoing_replies: person.outgoing_count, incoming_replies: person.incoming_count,
      recent_posts: recent.map { |post| { url: "https://x.com/#{person.handle}/status/#{post.x_id}", text: post.body.first(500), published_at: post.published_at.iso8601 } },
      accepted_recap: recap && { summary: recap.payload["summary"], accepted_at: recap.reviewed_at.iso8601 })
    context[:notes] = person.notes if @workspace.mcp_share_notes
    context
  end

  def get_interaction_history(args)
    person = find_person!(args)
    limit = bounded(args["limit"], 20, 50)
    bodies = X::SourcePost.where(x_id: person.reply_events.select(:x_id)).pluck(:x_id, :body).to_h
    events = person.reply_events.order(occurred_at: :desc).limit(limit).map do |event|
      { kind: "reply", direction: event.direction, classification: event.classification, at: event.occurred_at.iso8601,
        url: "https://x.com/i/web/status/#{event.x_id}", target_url: "https://x.com/i/web/status/#{event.target_x_id}",
        text: bodies[event.x_id]&.first(500) }.compact
    end
    if person.x_id
      events += Engagement.where(author_x_id: person.x_id).order(post_published_at: :desc).limit(limit).map do |engagement|
        { kind: engagement.kind, direction: "outgoing", at_or_after: [engagement.post_published_at, engagement.observed_after].compact.max.iso8601,
          url: "https://x.com/#{person.handle}/status/#{engagement.post_x_id}" }
      end
      if @workspace.mcp_share_dms
        events += person.direct_messages.order(occurred_at: :desc).limit(limit).map do |message|
          { kind: "dm", direction: message.direction, at: message.occurred_at.iso8601 }
        end
      end
    end
    coverage = Person::Interactions.coverage
    coverage = coverage.except("DMs") unless @workspace.mcp_share_dms
    { demo: @demo, person_id: person.id, handle: person.handle,
      events: events.sort_by { |event| -Time.iso8601(event[:at] || event[:at_or_after]).to_f }.first(limit),
      coverage: coverage, note: "Collected evidence only. Missing history is not proof that you never interacted." }
  end

  def list_pending_proposals(args)
    kind = args["kind"].presence
    raise Invalid, "kind must be one of #{(AI::Proposal::KINDS + %w[posts]).join(", ")}." if kind && !(AI::Proposal::KINDS + %w[posts]).include?(kind)
    limit = bounded(args["limit"], 25, 50)
    result = { demo: @demo, note: "Nothing here has applied yet. The owner accepts or dismisses each item in the app." }
    unless kind == "posts"
      proposals = AI::Proposal.pending.includes(:person).order(created_at: :desc)
      proposals = proposals.where(kind: kind) if kind
      result[:total] = proposals.count
      result[:proposals] = proposals.limit(limit).map do |proposal|
        { kind: proposal.kind, person: { id: proposal.person.id, handle: proposal.person.handle, name: proposal.person.name },
          proposed: proposal.payload, proposed_at: proposal.created_at.iso8601, via: proposal.via }
      end
    end
    if kind.nil? || kind == "posts"
      posts = Outreach::Candidate.opportunities.where(source: "ai").order(created_at: :desc)
      result[:unverified_posts_total] = posts.count
      result[:unverified_posts] = posts.limit(limit).map do |post|
        { url: "https://x.com/i/status/#{post.x_id}", text: post.body.to_s.first(280), reason: post.match_reason, proposed_at: post.created_at.iso8601 }
      end
    end
    result
  end

  def list_known_posts(args)
    since = bounded(args["days"], 7, 30).days.ago
    ids = Outreach::Candidate.where("published_at >= ? OR updated_at >= ?", since, since).pluck(:x_id)
    ids += ReplyEvent.where(direction: "outgoing", occurred_at: since..).pluck(:target_x_id)
    ids += X::SourcePost.where(published_at: since..).pluck(:x_id)
    { demo: @demo, since: since.iso8601, post_ids: ids.uniq.first(1000) }
  end

  def propose_candidate_posts(args)
    posts = args["posts"]
    raise Invalid, "posts must be an array of 1 to 20 items." unless posts.is_a?(Array) && posts.size.between?(1, AI::Intake::MAX_ITEMS)
    intake(args).call("posts" => posts).slice(:run_id, :posts)
  end

  def fill_profile_facts(args)
    intake(args).call("profiles" => [args.except("run_id")]).slice(:run_id, :profiles)
  end

  def save_recap(args)
    intake(args).call("recaps" => [args.except("run_id")]).slice(:run_id, :recaps)
  end

  def add_tags(args)
    assignments = args["assignments"]
    raise Invalid, "assignments must be an array of 1 to 50 items." unless assignments.is_a?(Array) && assignments.size.between?(1, AI::Intake::MAX_TAG_ITEMS)
    intake(args).call("tags" => assignments).slice(:run_id, :tags)
  end

  def add_note(args)
    intake(args).call("notes" => [args.except("run_id")]).slice(:run_id, :notes)
  end

  def set_reminder(args)
    intake(args).call("reminders" => [args.except("run_id")]).slice(:run_id, :reminders)
  end

  def list_ai_changes(args)
    status = args["status"].presence
    raise Invalid, "status must be one of #{AI::Proposal::STATUSES.join(', ')}." if status && !AI::Proposal::STATUSES.include?(status)
    changes = AI::Proposal.includes(:person).order(created_at: :desc)
    changes = changes.where(status: status) if status
    { apply_changes: @workspace.mcp_apply_changes,
      changes: changes.limit(bounded(args["limit"], 25, 50)).map { |change| change_summary(change) } }
  end

  def undo_ai_change(args)
    change = AI::Proposal.find_by(id: args["id"]) or raise Invalid, "Change not found. Use an id from list_ai_changes."
    return { undone: true, change: change_summary(change) } if change.status == "undone"
    raise Invalid, "Only applied or accepted changes can be undone; this one is #{change.status}." unless change.undoable?
    change.undo!
    { undone: true, change: change_summary(change) }
  end

  def get_follow_review_batch(args)
    cleanup = Follow::Cleanup.new(reason: args["reason"])
    return { ready: false, note: "No complete following list yet, so there is nothing to review." } unless cleanup.ready?
    people = cleanup.candidates(bounded(args["limit"], 25, 50))
    posts = cleanup.recent_posts(people)
    graph = Follow::Graph.latest
    interactions = Person::Interactions.index(people)
    { ready: true, reason: cleanup.reason, reason_label: Follow::Cleanup::REASONS[cleanup.reason], matching: cleanup.counts[cleanup.reason],
      interests: @workspace.interests, off_topic_tag: AI::Classification::OFF_TOPIC,
      people: people.map do |person|
        person_summary(person, graph, interactions.fetch(person.id)).merge(
          followers_count: person.followers_count, last_posted_at: person.last_posted_at&.iso8601,
          recent_posts: posts.fetch(person.x_id, []).map { |post| { text: CGI.unescapeHTML(post.body).first(400), published_at: post.published_at.iso8601 } })
      end,
      note: "Unknown activity is never inactive, and no collected interaction is not proof of none." }
  end

  def get_x_analytics(args)
    period = Network::Activity::PERIODS.key?(args["period"]) ? args["period"] : "30d"
    analytics = Network::XAnalytics.new(Network::Activity.new(period: period))
    return { collected: false, note: "No X analytics saved yet. The owner opens Analytics on x.com with the extension on to collect them." } unless analytics.any?
    payoff = Outreach::Payoff.new
    hours = Network::ActiveHours.new
    audience = analytics.audience
    { collected: true, period: period, days_collected: analytics.covered_days, as_of: analytics.observed_at&.iso8601,
      totals: analytics.totals, engagement_rate: analytics.engagement_rate&.round(4),
      replies: { counted: analytics.replies.size, totals: analytics.reply_totals, timing: analytics.reply_timing(hours),
        by_account_size: payoff.bands.values.map { |band| band.to_h.merge(per_reply: band.per_reply.round(2)) },
        best: analytics.best_replies.first(8).map { |reply| { to: reply.event.person.handle, url: "https://x.com/i/status/#{reply.event.x_id}",
          text: CGI.unescapeHTML(reply.analytics.body.to_s).first(280), impressions: reply.impressions, profile_visits: reply.visits, follows: reply.follows } } },
      top_posts: analytics.posts.map { |post| { url: "https://x.com/i/status/#{post.post_x_id}", text: CGI.unescapeHTML(post.body.to_s).first(280),
        published_at: post.published_at&.iso8601, metrics: post.metrics } },
      busy_hours: hours.collected? ? busy_hours(hours) : nil,
      audience: audience && { from_non_followers: audience.outside_network_share&.round(3), english_speaking: audience.english_share&.round(3),
        top_countries: audience.countries(8).map { |code, share| { country: code, share: share.round(3) } } },
      note: "Figures are X's own, as of when the owner last opened each analytics page; days not collected are missing, not zero." }
  end

  def get_growth_plan(args)
    growth = Outreach::Growth.new
    return { started: false, followers: growth.followers, note: "The owner hasn't started a growth plan; they start one on Xtend's Growth page." } unless growth.started?
    number = Integer(args["week"] || growth.current_week.clamp(1, Outreach::Growth::WEEKS), exception: false)
    raise Invalid, "week must be 1 to #{Outreach::Growth::WEEKS}." unless number&.between?(1, Outreach::Growth::WEEKS)
    week = growth.week(number)
    { started_on: growth.started_on.iso8601, goal: growth.goal, start_followers: growth.start_followers, current_week: growth.current_week,
      followers_now: growth.latest_followers&.then { |count, at, source| { count: count, at: at.iso8601, source: source } },
      week: { number: number, from: week.starts_on.iso8601, to: week.ends_on.iso8601, followers: week.followers, checkpoint: week.followers_target,
        on_track: growth.on_track?(week), profile_visits: week.visits, visits_aim: week.visits_target, analytics_days: week.analytics_days,
        review: Outreach::Growth::REVIEWS[number] },
      checklist: growth.checklist(number).map { |key, label, _why, kind, done, detail| { key: key, item: label, done: done, ticked_by: kind == :auto ? "Xtend" : "The owner", detail: detail }.compact },
      circle: growth.circle_members(number).map { |member| { handle: member.person.handle, person_id: member.person.id, followers: member.person.followers_count,
        replied_this_week: member.replied_this_week, last_reply_at: member.last_reply_at&.iso8601,
        fresh_post: member.fresh_post && { url: "https://x.com/i/status/#{member.fresh_post.x_id}", text: CGI.unescapeHTML(member.fresh_post.body).first(280) } } },
      note: "Checkpoints are aims, not forecasts. Followers are the newest count Xtend had by the week's end; missing means not collected." }
  end

  def get_week_review(args)
    weeks_ago = Integer(args["weeks_ago"] || 0, exception: false)
    raise Invalid, "weeks_ago must be 0 to #{Network::Week::MAX_WEEKS_AGO}." unless weeks_ago&.between?(0, Network::Week::MAX_WEEKS_AGO)
    week = Network::Week.new(weeks_ago: weeks_ago)
    reply = week.best_reply
    totals = week.analytics_totals if week.analytics_days.any?
    { from: week.starts_at.to_date.iso8601, to: week.ends_at.to_date.iso8601,
      did: { replies: week.replies.count, new_targets: week.new_targets, follow_ups: week.follow_ups, people_talked_with: week.people_count },
      brought: { replies_to_you: week.replies_to_you, answered: week.answers_seen, answers_may_be_missing: week.answers_incomplete?,
        analytics_days: week.analytics_days.size, analytics: totals&.slice(:impressions, :profile_visits, :follows, :engagements),
        follower_change: week.follower_change&.then { |gained, lost| { gained: gained, lost: lost } } },
      best_reply: reply && { to: reply.event.person.handle, url: "https://x.com/i/status/#{reply.event.x_id}", text: CGI.unescapeHTML(reply.analytics.body.to_s).first(280),
        impressions: reply.impressions, profile_visits: reply.visits, follows: reply.follows },
      best_post: week.best_post&.then { |post| post.merge(url: "https://x.com/i/status/#{post[:x_id]}", body: CGI.unescapeHTML(post[:body].to_s).first(280)) },
      next: { replies_waiting: week.waiting_count,
        reminders_due: week.reminders.map { |reminder| { person: reminder.person.handle, reason: reminder.reason, due_on: reminder.due_on.iso8601 } },
        gone_quiet: week.gone_quiet.map { |prospect| { person: prospect.handle, person_id: prospect.person&.id, detail: prospect.reasons.find { _1.key == "quiet" }&.detail } } } }
  end

  def get_task(args)
    Mcp::Prompts.get(args["task"], args.slice("handle"))
  rescue ArgumentError => error
    raise Invalid, error.message
  end

  def list_network_posts(args)
    person = find_person!(args) if args["person_id"].present? || args["handle"].present?
    timeline = Network::Timeline.new(who: args["who"], kind: args["kind"], sort: args["sort"], period: args["period"], tag: args["tag"],
      person: person, query: args["query"], media: args["with_media"] ? "1" : nil)
    limit = bounded(args["limit"], 20, 40)
    { total: timeline.count, coverage: "Only posts captured from x.com or collected through the API; counts are as last seen.",
      posts: timeline.posts.first(limit).map { |post| network_post(post, timeline) } }
  end

  def get_network(args)
    period = Network::Graph::PERIODS.key?(args["period"]) ? args["period"] : "90d"
    if args["person_id"].present? || args["handle"].present?
      person = find_person!(args)
      neighborhood = Network::Neighborhood.new(person)
      return { person: { id: person.id, handle: person.handle, name: person.name },
        interacts_with: neighborhood.partners.map { |partner, kinds| { id: partner.id, handle: partner.handle, name: partner.name, interactions: kinds } },
        followed_by: neighborhood.followed_by.map { |other| { id: other.id, handle: other.handle } },
        follows: neighborhood.follows.map { |other| { id: other.id, handle: other.handle } },
        saved_posts: neighborhood.saved_posts, coverage: "Partial: only what was captured or collected." }
    end
    graph = Network::Graph.new(period: period, tag: args["tag"], include_owner: false, outside: true)
    handles = graph.nodes.to_h { |node| [ node[:id], node[:handle] ] }
    { period: period,
      most_connected: graph.nodes.reject { |node| node[:outside] }.sort_by { |node| -node[:weight] }.first(20).map { |node| node.slice(:handle, :name, :person_id, :follow_state, :tags, :weight) },
      busiest_pairs: graph.links.sort_by { |link| -link[:weight] }.first(20).map { |link| { from: handles[link[:source]], to: handles[link[:target]], interactions: link[:kinds] } },
      outside_accounts: graph.nodes.select { |node| node[:outside] }.sort_by { |node| -node[:weight] }.first(20).map { |node| node.slice(:handle, :name, :followers, :weight) },
      people_without_connections: graph.isolated_count, coverage: "Partial: only what was captured or collected." }
  end

  def list_post_drafts(args)
    stage = args["stage"]
    raise Invalid, "stage must be one of #{Draft::STATUSES.keys.join(", ")}." if stage && !Draft::STATUSES.key?(stage)
    drafts = (stage ? Draft.in_status(stage) : Draft.where.not(status: "posted")).recent.includes(:alternatives).limit(bounded(args["limit"], 10, 25))
    { drafts: drafts.map { |draft| draft_summary(draft) } }
  end

  def get_post_performance(args)
    performance = Network::PostPerformance.new(since: bounded(args["days"], 90, 365).days.ago)
    { compared: performance.settled.size, too_fresh: performance.fresh_count, without_counts: performance.uncounted_count,
      by_format: performance.by_format.map { |row| { format: row.format, posts: row.posts, median_views: row.views, median_likes: row.likes, median_replies: row.replies, people_who_replied: row.people } },
      top_posts: performance.top(10).map { |post| { url: post.url, text: CGI.unescapeHTML(post.body), published_at: post.published_at.iso8601, format: post.format,
        views: post.view_count, likes: post.like_count, replies: post.reply_count, reposts: post.repost_count, people_who_replied: post.people } },
      coverage: "Counts as last seen by the browser capture; posts never seen with counts are left out." }
  end

  def save_post_idea(args)
    texts = variation_texts(args["texts"])
    stage = args["stage"].presence || "idea"
    raise Invalid, "stage must be idea or drafting." unless %w[idea drafting].include?(stage)
    draft = Draft.capture!(texts: texts, editor: "ai", note: args["variation_note"].to_s.first(200).presence, status: stage,
      topic: args["topic"].to_s.first(120).presence, notes: args["notes"].to_s.first(2000).presence, inspiration_url: args["inspiration_url"].presence)
    { saved: true, draft: draft_summary(draft) }
  rescue ActiveRecord::RecordInvalid => error
    raise Invalid, error.record.errors.full_messages.to_sentence
  end

  def add_post_variations(args)
    draft = Draft.find_by(id: args["draft_id"]) or raise Invalid, "Draft not found. Use an id from list_post_drafts."
    draft.add_alternatives!(variation_texts(args["texts"]), source: "ai", note: args["note"].to_s.first(200).presence)
    { saved: true, draft: draft_summary(draft.reload) }
  rescue ActiveRecord::RecordInvalid => error
    raise Invalid, error.record.errors.full_messages.to_sentence
  end

  private

  def busy_hours(hours)
    days = %w[Mon Tue Wed Thu Fri Sat Sun]
    busy = hours.slots.select { |(wday, hour), _| hours.level(Time.current.beginning_of_week + wday.days + hour.hours) == :busy }
    { time_zone: Time.zone.tzinfo.name, as_of: hours.newest&.iso8601,
      busiest: busy.sort_by { |_, value| -value }.first(12).map { |(wday, hour), value| { day: days[wday], hour: hour, average_impressions: value.round(1) } } }
  end

  def change_summary(change)
    { id: change.id, kind: change.kind, status: change.status, person: { id: change.person.id, handle: change.person.handle },
      change: change.payload, at: change.created_at.iso8601, via: change.via, undone_at: change.undone_at&.iso8601 }.compact
  end

  def variation_texts(texts)
    texts = Array(texts).map { |text| text.to_s.strip.first(5000) }.reject(&:blank?) if texts.is_a?(Array)
    raise Invalid, "texts must be an array of 1 to #{MAX_VARIATIONS} non-empty strings." unless texts.is_a?(Array) && texts.size.between?(1, MAX_VARIATIONS)
    texts
  end

  def network_post(post, timeline)
    author = timeline.people[post.author_x_id] || timeline.accounts[post.author_x_id]
    quoted = timeline.quoted[post.quoted_x_id]
    { url: "https://x.com/i/status/#{post.x_id}", author: author&.handle || (post.author_x_id == Current.workspace.owner_x_id ? "david" : nil),
      text: CGI.unescapeHTML(post.body), published_at: post.published_at.iso8601, reply: post.reply_to_x_id.present?,
      counts: post.slice(:reply_count, :like_count, :repost_count, :quote_count, :bookmark_count, :view_count).compact,
      counts_as_of: post.metrics_observed_at&.iso8601, media: post.media_kinds&.split(","), has_link: post.has_link,
      quoted_text: quoted && CGI.unescapeHTML(quoted.body).first(500) }.compact
  end

  def draft_summary(draft)
    { id: draft.id, stage: draft.status, written_by: draft.source == "ai" ? "ai" : "david", topic: draft.topic, notes: draft.notes,
      text: draft.body, posts: draft.parts.size, weighted_lengths: draft.part_lengths, over_limit: draft.over_limit?,
      alternatives: draft.alternatives.map { |alternative| { text: alternative.body, written_by: alternative.source == "ai" ? "ai" : "david", note: alternative.note } },
      updated_at: draft.updated_at.iso8601 }
  end

  def intake(args)
    AI::Intake.new(via: "mcp", run_id: args["run_id"])
  end

  def person_summary(person, graph, interactions)
    latest = interactions.signals.reject { |signal| signal.channel == "dm" && !@workspace.mcp_share_dms }.first
    { id: person.id, handle: person.handle, name: person.name, description: person.description&.first(300),
      followers: person.followers_count, follow_state: person.follow_state(graph), reply_state: person.reply_state, tags: person.tags.map(&:name),
      pinned: person.pin.present?, keep_following: person.follow_protection.present?,
      last_interaction: latest && { channel: latest.channel, direction: latest.direction, at: latest.at.iso8601, approximate: latest.approximate? } }
  end

  def find_person!(args)
    person = if args["person_id"].present?
      Person.find_by(id: args["person_id"])
    elsif args["handle"].present?
      Person.find_by(handle: args["handle"].to_s.delete_prefix("@").downcase.strip)
    end
    person || raise(Invalid, "Person not found. Use an id or handle from list_people.")
  end

  def bounded(value, default, maximum)
    number = value.nil? ? default : Integer(value, exception: false)
    raise Invalid, "Use a whole number between 1 and #{maximum}." unless number&.between?(1, maximum)
    number
  end
end
