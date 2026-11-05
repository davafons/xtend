# Tools that Grok Bot (or any MCP client) can call. Reads are bounded and scoped by the owner's sharing choices;
# writes only stage research through Grok::Intake. No tool posts, follows, messages, or runs paid X reads.
class Mcp::Tools
  class Invalid < StandardError; end

  PERSON_REF = {
    person_id: { type: "integer", description: "CRM person ID from list_people." },
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

  DEFINITIONS = [
    { name: "get_owner_profile", title: "Owner interests and rules",
      description: "The owner's interests, the daily reply goal, discovery filters, and which private categories he shares.",
      inputSchema: { type: "object", properties: {} }, annotations: { readOnlyHint: true } },
    { name: "get_session_state", title: "Today's session",
      description: "Progress toward 20 distinct new reply targets, plus post IDs already replied to, set aside, or reported. Use it to avoid duplicates.",
      inputSchema: { type: "object", properties: {} }, annotations: { readOnlyHint: true } },
    { name: "list_people", title: "List people",
      description: "Bounded list of people in the CRM with follow state, reply state, tags, pins, keeps, and last observed interaction.",
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
    { name: "list_known_posts", title: "Known post IDs",
      description: "Post IDs already in the CRM within a window, so proposals skip duplicates.",
      inputSchema: { type: "object", properties: { days: { type: "integer", minimum: 1, maximum: 30 } } },
      annotations: { readOnlyHint: true } },
    { name: "propose_candidate_posts", title: "Propose reply targets",
      description: "Stage up to 20 public posts as unverified reply candidates in the owner's Today queue. Does not reply or mark anything sent.",
      inputSchema: { type: "object", required: %w[posts], properties: {
        run_id: { type: "string" }, posts: { type: "array", maxItems: 20, items: CANDIDATE } } },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true } },
    { name: "propose_person_facts", title: "Propose profile facts",
      description: "Stage public profile facts for an existing person. Accepted facts only fill fields the CRM does not have.",
      inputSchema: { type: "object", properties: PERSON_REF.merge(
        name: { type: "string" }, description: { type: "string" }, location: { type: "string" },
        website_url: { type: "string" }, followers_count: { type: "integer" }, following_count: { type: "integer" },
        observed_at: { type: "string" }, run_id: { type: "string" }) },
      annotations: { readOnlyHint: false, destructiveHint: false } },
    { name: "propose_recap", title: "Propose a person recap",
      description: "Stage a short evidence-linked summary of who someone is and what they are working on, for the owner to review.",
      inputSchema: { type: "object", required: %w[summary], properties: PERSON_REF.merge(
        summary: { type: "string", maxLength: 1500 },
        evidence_urls: { type: "array", maxItems: 10, items: { type: "string" } }, run_id: { type: "string" }) },
      annotations: { readOnlyHint: false, destructiveHint: false } },
    { name: "propose_tags", title: "Propose tags",
      description: "Stage tags for up to 50 existing people, such as a city, role, or topic, so the owner can group them. Reuse tags from get_owner_profile where they fit. Nothing applies until the owner accepts.",
      inputSchema: { type: "object", required: %w[assignments], properties: {
        run_id: { type: "string" },
        assignments: { type: "array", maxItems: 50, items: { type: "object", required: %w[tags], properties: PERSON_REF.merge(
          tags: { type: "array", maxItems: 8, items: { type: "string", maxLength: 40 } },
          reason: { type: "string", description: "Short public evidence for the tags, such as the bio or recent posts." }) } } } },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true } }
  ].freeze

  def self.definitions = DEFINITIONS
  def self.names = DEFINITIONS.map { |tool| tool[:name] }

  def initialize
    @workspace = Current.workspace
    @demo = Rails.configuration.x.demo
  end

  def get_owner_profile(_args)
    { demo: @demo, handle: X::Connection.current&.username, interests: @workspace.interests,
      session_goal: "Replies on #{DailySession::TARGET} distinct new target posts per session. Follow-ups in existing exchanges do not count.",
      discovery_filters: ["English only", "Posted in the last 7 days", "At most 50 replies", "No crypto, airdrops, engagement bait, follow-for-follow, or pure promotion", "No automated accounts"],
      tags: Tag.by_use.limit(200).map { |tag| { name: tag.name, people: tag.people_count } },
      shared_categories: { notes: @workspace.mcp_share_notes, dm_metadata: @workspace.mcp_share_dms },
      rules: "Reading or proposing never sends anything. The owner replies manually on X." }
  end

  def get_session_state(_args)
    session = DailySession.current
    hidden = PostDisposition.where(kind: "skipped").or(PostDisposition.where("until_at > ?", Time.current))
    { demo: @demo, target: DailySession::TARGET, progress: session.progress,
      remaining: [DailySession::TARGET - session.progress, 0].max,
      queue: { available: Post.opportunities.count, unverified_from_grok: Post.opportunities.where(source: "grok").count },
      replied_post_ids: ReplyEvent.where(direction: "outgoing").order(occurred_at: :desc).limit(200).pluck(:target_x_id),
      set_aside_post_ids: Post.where(id: hidden.select(:post_id)).order(updated_at: :desc).limit(200).pluck(:x_id),
      reported_post_ids: Post.where(id: ReplyReport.select(:post_id)).pluck(:x_id) }
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
    following = graph.following&.follow_memberships&.select(:person_id)
    followers = graph.followers&.follow_memberships&.select(:person_id)
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
    recap = person.grok_proposals.latest_recap
    context = person_summary(person, graph, person.interactions).merge(
      profile_url: person.profile_url, location: person.location, website_url: person.website_url,
      followers_count: person.followers_count, following_count: person.following_count,
      profile_source: person.x_id ? "x_api" : "grok_research_unverified",
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

  def list_known_posts(args)
    since = bounded(args["days"], 7, 30).days.ago
    ids = Post.where("published_at >= ? OR updated_at >= ?", since, since).pluck(:x_id)
    ids += ReplyEvent.where(direction: "outgoing", occurred_at: since..).pluck(:target_x_id)
    ids += X::SourcePost.where(published_at: since..).pluck(:x_id)
    { demo: @demo, since: since.iso8601, post_ids: ids.uniq.first(1000) }
  end

  def propose_candidate_posts(args)
    posts = args["posts"]
    raise Invalid, "posts must be an array of 1 to 20 items." unless posts.is_a?(Array) && posts.size.between?(1, Grok::Intake::MAX_ITEMS)
    intake(args).call("posts" => posts).slice(:run_id, :posts)
  end

  def propose_person_facts(args)
    intake(args).call("profiles" => [args.except("run_id")]).slice(:run_id, :profiles)
  end

  def propose_recap(args)
    intake(args).call("recaps" => [args.except("run_id")]).slice(:run_id, :recaps)
  end

  def propose_tags(args)
    assignments = args["assignments"]
    raise Invalid, "assignments must be an array of 1 to 50 items." unless assignments.is_a?(Array) && assignments.size.between?(1, Grok::Intake::MAX_TAG_ITEMS)
    intake(args).call("tags" => assignments).slice(:run_id, :tags)
  end

  private

  def intake(args)
    Grok::Intake.new(via: "mcp", run_id: args["run_id"])
  end

  def person_summary(person, graph, interactions)
    latest = interactions.signals.reject { |signal| signal.channel == "dm" && !@workspace.mcp_share_dms }.first
    { id: person.id, handle: person.handle, name: person.name, description: person.description&.first(300),
      follow_state: person.follow_state(graph), reply_state: person.reply_state, tags: person.tags.map(&:name),
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
