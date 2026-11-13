# Tools that any MCP client (Grok Bot, Claude, ChatGPT, ...) can call. Reads are bounded and scoped by the owner's sharing
# choices; writes stage research through Grok::Intake or save post drafts. No tool posts, follows, messages, applies
# changes without owner review, or runs paid X reads. Grok::* is the internal name for all AI research.
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

  MAX_VARIATIONS = 10

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
    { name: "list_pending_proposals", title: "Proposals awaiting review",
      description: "Tags, recaps, and profile facts staged for the owner that he has not accepted or dismissed yet, plus unverified reply targets still in his Today queue. Check it before proposing so you add to the queue instead of repeating it.",
      inputSchema: { type: "object", properties: {
        kind: { type: "string", enum: Grok::Proposal::KINDS + %w[posts], description: "Only one kind. Defaults to all." },
        limit: { type: "integer", minimum: 1, maximum: 50 } } },
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
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true } },
    { name: "list_network_posts", title: "Network posts",
      description: "Posts from the owner's network that he collected or scrolled past on x.com, with the counts last seen (likes, reposts, replies, quotes, bookmarks, views). Use them as references for style and topics. Counts are not live, and coverage is only what was captured.",
      inputSchema: { type: "object", properties: PERSON_REF.merge(
        who: { type: "string", enum: Network::Timeline::WHO.keys, description: "network (default): The owner's people and the owner; seen: everything he was shown." },
        kind: { type: "string", enum: Network::Timeline::KINDS.keys, description: "Defaults to posts (no replies)." },
        sort: { type: "string", enum: Network::Timeline::SORTS.keys },
        period: { type: "string", enum: Network::Timeline::PERIODS.keys, description: "Defaults to 30d." },
        tag: { type: "string" }, query: { type: "string", description: "Text the post contains." },
        with_media: { type: "boolean" }, limit: { type: "integer", minimum: 1, maximum: 40 }) },
      annotations: { readOnlyHint: true } },
    { name: "get_network", title: "Network connections",
      description: "Who interacts with whom among the owner's people (replies, quotes, reposts, mentions, likes) and captured follow edges. With a person, their connections; without, the most connected people, the busiest pairs, and outside accounts several of his people talk to. A missing connection is not proof of none.",
      inputSchema: { type: "object", properties: PERSON_REF.merge(
        period: { type: "string", enum: Network::Graph::PERIODS.keys, description: "Defaults to 90d." },
        tag: { type: "string" }) },
      annotations: { readOnlyHint: true } },
    { name: "list_post_drafts", title: "List post drafts",
      description: "The owner's saved ideas and drafts for his own posts, newest first, with their alternative versions. Use draft IDs with add_post_variations.",
      inputSchema: { type: "object", properties: {
        stage: { type: "string", enum: Draft::STATUSES.keys, description: "Defaults to every stage except posted." },
        limit: { type: "integer", minimum: 1, maximum: 25 } } },
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
      queue: { available: Post.opportunities.count, unverified_from_ai: Post.opportunities.where(source: "grok").count },
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
    recap = person.grok_proposals.latest_recap
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
    raise Invalid, "kind must be one of #{(Grok::Proposal::KINDS + %w[posts]).join(", ")}." if kind && !(Grok::Proposal::KINDS + %w[posts]).include?(kind)
    limit = bounded(args["limit"], 25, 50)
    result = { demo: @demo, note: "Nothing here has applied yet. The owner accepts or dismisses each item in the app." }
    unless kind == "posts"
      proposals = Grok::Proposal.pending.includes(:person).order(created_at: :desc)
      proposals = proposals.where(kind: kind) if kind
      result[:total] = proposals.count
      result[:proposals] = proposals.limit(limit).map do |proposal|
        { kind: proposal.kind, person: { id: proposal.person.id, handle: proposal.person.handle, name: proposal.person.name },
          proposed: proposal.payload, proposed_at: proposal.created_at.iso8601, via: proposal.via }
      end
    end
    if kind.nil? || kind == "posts"
      posts = Post.opportunities.where(source: "grok").order(created_at: :desc)
      result[:unverified_posts_total] = posts.count
      result[:unverified_posts] = posts.limit(limit).map do |post|
        { url: "https://x.com/i/status/#{post.x_id}", text: post.body.to_s.first(280), reason: post.match_reason, proposed_at: post.created_at.iso8601 }
      end
    end
    result
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

  def save_post_idea(args)
    texts = variation_texts(args["texts"])
    stage = args["stage"].presence || "idea"
    raise Invalid, "stage must be idea or drafting." unless %w[idea drafting].include?(stage)
    draft = Draft.capture!(texts: texts, editor: "grok", note: args["variation_note"].to_s.first(200).presence, status: stage,
      topic: args["topic"].to_s.first(120).presence, notes: args["notes"].to_s.first(2000).presence, inspiration_url: args["inspiration_url"].presence)
    { saved: true, draft: draft_summary(draft) }
  rescue ActiveRecord::RecordInvalid => error
    raise Invalid, error.record.errors.full_messages.to_sentence
  end

  def add_post_variations(args)
    draft = Draft.find_by(id: args["draft_id"]) or raise Invalid, "Draft not found. Use an id from list_post_drafts."
    draft.add_alternatives!(variation_texts(args["texts"]), source: "grok", note: args["note"].to_s.first(200).presence)
    { saved: true, draft: draft_summary(draft.reload) }
  rescue ActiveRecord::RecordInvalid => error
    raise Invalid, error.record.errors.full_messages.to_sentence
  end

  private

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
    { id: draft.id, stage: draft.status, written_by: draft.source == "grok" ? "ai" : "david", topic: draft.topic, notes: draft.notes,
      text: draft.body, posts: draft.parts.size, weighted_lengths: draft.part_lengths, over_limit: draft.over_limit?,
      alternatives: draft.alternatives.map { |alternative| { text: alternative.body, written_by: alternative.source == "grok" ? "ai" : "david", note: alternative.note } },
      updated_at: draft.updated_at.iso8601 }
  end

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
