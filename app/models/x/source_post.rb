class X::SourcePost < ApplicationRecord
  include WorkspaceScoped
  belongs_to :x_sync_run, class_name: "X::SyncRun"
  validates :x_id, uniqueness: { scope: :workspace_id }
  # Posts read from the X API. Captured and archived posts never queue paid lookups.
  scope :collected, -> { joins(:x_sync_run).where(x_sync_runs: { mode: %w[backfill refresh] }) }

  # Each author's newest top-level post since a time that the owner hasn't replied to: { author_x_id => post }.
  def self.fresh_unanswered(author_x_ids, since: 48.hours.ago)
    answered = ReplyEvent.where(direction: "outgoing").select(:target_x_id)
    where(author_x_id: author_x_ids.compact, repost: false, reply_to_x_id: nil, published_at: since..)
      .where.not(x_id: answered).order(published_at: :desc).group_by(&:author_x_id).transform_values(&:first)
  end

  # Each author's newest top-level post ever collected: { author_x_id => post }.
  def self.latest_by(author_x_ids)
    newest = where(author_x_id: author_x_ids.compact, repost: false, reply_to_x_id: nil).group(:author_x_id).maximum(:published_at)
    return {} if newest.empty?
    where(author_x_id: newest.keys, published_at: newest.values, repost: false, reply_to_x_id: nil)
      .select { newest[_1.author_x_id] == _1.published_at }.index_by(&:author_x_id)
  end

  COUNTS = %i[like_count repost_count quote_count bookmark_count view_count].freeze

  # details come from browser captures: counts, media, links, and quote/repost ids. Counts only move forward in
  # time, so a sighting without counts never erases earlier ones.
  def self.capture!(row, run:, details: nil, at: Time.current)
    references = row.fetch("referenced_posts")
    parent = references.find { |ref| ref.fetch("type") == "replied_to" }
    record = find_or_initialize_by(x_id: row.fetch("id"))
    record.assign_attributes(author_x_id: row.fetch("author_id"), parent_x_id: parent&.fetch("id"),
      reply_to_x_id: row["in_reply_to_user_id"], conversation_x_id: row["conversation_id"],
      body: row.fetch("text"), language: row["lang"], published_at: Time.iso8601(row.fetch("created_at")),
      repost: references.any? { |ref| ref.fetch("type") == "retweeted" })
    record.reply_count = row["reply_count"] if row.key?("reply_count")
    record.first_seen_at ||= at
    if details
      record.assign_attributes(details.slice(:quoted_x_id, :reposted_x_id).compact)
      # A post's media and links don't change, but a sighting can omit them (a repost, a trimmed embed).
      record.media_kinds = details[:media_kinds] if details[:media_kinds]
      record.has_link ||= details[:has_link] == true
      counts = details.slice(*COUNTS).compact
      record.assign_attributes(counts.merge(metrics_observed_at: at)) if counts.any?
    end
    record.x_sync_run = run if record.x_sync_run.nil? || record.x_sync_run.outranked_by?(run)
    record.save!
    record.record_reply_interaction
  end

  def record_reply_interaction
    return unless reply_to_x_id
    X::Interaction.record!(kind: "reply", source: author_x_id, target: reply_to_x_id, post: x_id, target_post: parent_x_id, occurred_at: published_at)
  end

  def self.reconcile_all!
    includes(:x_sync_run).find_each(&:reconcile!)
  end

  def reconcile!
    owner = Current.workspace.owner_x_id
    return if repost || published_at > Time.current
    proposed = Outreach::Candidate.exists?(x_id: x_id, source: "ai")
    person = Person.find_by(x_id: author_x_id) || (Person.bind_ai_author!(post_x_id: x_id, author_x_id: author_x_id) if proposed) unless author_x_id == owner
    discovery = proposed || x_sync_run.discovery_posts?
    if person && discovery
      post = Outreach::Candidate.find_or_initialize_by(x_id: x_id)
      assessment = Outreach::Assessment.call(body: body, description: person.description,
        interests: Current.workspace.interests, handle: person.handle, selected: proposed)
      keep_reason = proposed && post.rank >= 0 && assessment[:rank] >= 0
      post.assign_attributes(person: person, body: body, language: language.presence || "und", published_at: published_at,
        topic: post.topic.presence || "Builder conversations", rank: assessment[:rank], reply_count: reply_count,
        match_reason: keep_reason ? post.match_reason : assessment[:reason], source: source)
      post.save!
    end
    return unless parent_x_id
    parent = self.class.find_by(x_id: parent_x_id)
    target_author = reply_to_x_id || parent&.author_x_id
    direction = if author_x_id == owner && target_author.present? && target_author != owner
      "outgoing"
    elsif author_x_id != owner && target_author == owner
      "incoming"
    end
    return unless direction
    person = Person.find_by(x_id: direction == "outgoing" ? target_author : author_x_id)
    person ||= Person.bind_ai_author!(post_x_id: parent_x_id, author_x_id: target_author) if direction == "outgoing"
    return unless person
    classification = direction == "outgoing" ? outreach_classification(owner) : "continuation"
    ReplyEvent.ingest_verified!(profile: { x_id: person.x_id, handle: person.handle, name: person.name },
      x_id: x_id, target_x_id: parent_x_id, direction: direction, classification: classification, source: source,
      occurred_at: published_at, confirmed_at: Time.current, outreach_eligible: %w[refresh capture].include?(x_sync_run.mode))
  end

  def source
    { "capture" => "x_capture", "archive" => "archive" }.fetch(x_sync_run.mode, "x_api")
  end

  def outreach_classification(owner)
    earlier = self.class.where(author_x_id: owner, repost: false).where.not(x_id: x_id).where("published_at < ?", published_at)
    if conversation_x_id.present?
      return "continuation" if earlier.where(conversation_x_id: conversation_x_id).where.not(parent_x_id: nil).exists?
    end
    # Archived posts carry no conversation, but a second reply to the same post is still a follow-up.
    return "continuation" if earlier.exists?(parent_x_id: parent_x_id)
    ancestor = self.class.find_by(x_id: parent_x_id)
    return ai_target_classification(owner) if ancestor.nil? && Outreach::Candidate.exists?(x_id: parent_x_id, source: "ai")
    visited = [x_id]
    40.times do
      return "unclassified" unless ancestor
      return "continuation" if ancestor.author_x_id == owner || ancestor.reply_to_x_id == owner
      return "initial" if ancestor.parent_x_id.nil?
      return "unclassified" if visited.include?(ancestor.x_id)
      visited << ancestor.x_id
      ancestor = self.class.find_by(x_id: ancestor.parent_x_id)
    end
    "unclassified"
  end

  # The target came from AI and was never read from X, so its ancestors are unknown. X still confirms the
  # reply's conversation, so a reply inside the owner's own thread or answering an incoming reply stays a follow-up.
  def ai_target_classification(owner)
    return "continuation" if conversation_x_id.present? && self.class.exists?(x_id: conversation_x_id, author_x_id: owner)
    return "continuation" if ReplyEvent.exists?(x_id: parent_x_id, direction: "incoming")
    "initial"
  end
end
