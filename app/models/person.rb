class Person < ApplicationRecord
  include WorkspaceScoped
  has_one :pin, dependent: :destroy
  has_one :follow_protection, class_name: "Follow::Protection", dependent: :destroy
  has_many :follower_periods, class_name: "Follow::FollowerPeriod", dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :reply_events, dependent: :destroy
  has_many :follow_memberships, class_name: "Follow::Membership", dependent: :destroy
  has_many :follow_reviews, class_name: "Follow::Review", dependent: :destroy
  has_many :engagements, primary_key: :x_id, foreign_key: :author_x_id, inverse_of: false
  has_many :direct_messages, primary_key: :x_id, foreign_key: :partner_x_id, inverse_of: false
  has_many :grok_proposals, class_name: "Grok::Proposal", dependent: :destroy
  has_many :person_tags, dependent: :destroy
  has_many :tags, -> { order(:name) }, through: :person_tags

  before_validation { self.handle = handle.to_s.delete_prefix("@").downcase.strip }
  validates :handle, presence: true, uniqueness: { scope: :workspace_id }, format: { with: /\A[a-z0-9_]{1,15}\z/ }
  validates :name, presence: true
  validates :x_id, uniqueness: { scope: :workspace_id }, allow_nil: true
  validates :x_id, format: { with: /\A\d{1,30}\z/ }, allow_nil: true

  scope :alphabetical, -> { order(:name) }
  scope :pinned, -> { joins(:pin) }
  scope :tagged, ->(name) { where(id: PersonTag.joins(:tag).where(tags: { name: Tag.normalize(name) }).select(:person_id)) }
  scope :untagged, -> { where.not(id: PersonTag.select(:person_id)) }

  # Adds tags without touching existing ones; returns the tags that were new for this person.
  def add_tags!(names, source: "owner")
    transaction do
      Tag.names_from(names).filter_map do |name|
        tag = Tag.named(name)
        next if person_tags.exists?(tag: tag)
        person_tags.create!(tag: tag, source: source)
        tag
      end
    end
  end

  PROFILE_DETAILS = %i[avatar_url banner_url location website_url followers_count following_count posts_count joined_x_at].freeze

  def self.profile_from_x(row)
    { x_id: row.fetch("id"), handle: row.fetch("username"), name: row.fetch("name"), description: row["description"],
      avatar_url: row["profile_image_url"], banner_url: row["profile_banner_url"], location: row["location"].presence,
      website_url: row["website_url"], followers_count: row["followers_count"], following_count: row["following_count"],
      posts_count: row["posts_count"], joined_x_at: row["created_at"] && Time.iso8601(row["created_at"]) }
  end

  def self.resolve_profile!(profile)
    x_id = profile.fetch(:x_id).to_s
    raise ArgumentError, "A source profile needs a stable numeric X ID." unless x_id.match?(/\A\d{1,30}\z/)
    handle = profile.fetch(:handle).to_s.delete_prefix("@").downcase.strip
    person = find_by(x_id: x_id) || find_by(handle: handle, x_id: nil) || new
    person.assign_attributes(profile.slice(:name, :description).merge(handle: handle, x_id: x_id))
    details = profile.slice(*PROFILE_DETAILS).compact
    person.assign_attributes(details.merge(profile_observed_at: Time.current)) if details.any?
    person.save!
    person
  end

  # Known only from Grok research: no X read has tied this handle to a numeric account yet.
  def grok_only?
    x_id.nil? && posts.where(source: "grok").exists?
  end

  def fill_blank_profile!(facts)
    blanks = facts.to_h.stringify_keys.select { |key, value| value.present? && self[key].blank? }
    update!(blanks) if blanks.any?
  end

  # X says post_x_id was written by author_x_id. If a Grok-only person holds that post, bind them to the real account;
  # if another record already has that X ID, move the post there.
  def self.bind_grok_author!(post_x_id:, author_x_id:)
    post = Post.find_by(x_id: post_x_id, source: "grok")
    return unless post && author_x_id.to_s.match?(/\A\d{1,30}\z/)
    if (existing = find_by(x_id: author_x_id))
      post.update!(person: existing) unless post.person_id == existing.id
      existing
    elsif post.person.x_id.nil?
      post.person.update!(x_id: author_x_id)
      post.person
    end
  end

  def outgoing_count
    reply_events.loaded? ? reply_events.count { |event| event.direction == "outgoing" } : reply_events.where(direction: "outgoing").count
  end

  def incoming_count
    reply_events.loaded? ? reply_events.count { |event| event.direction == "incoming" } : reply_events.where(direction: "incoming").count
  end

  def reply_state
    if outgoing_count.positive? && incoming_count.positive?
      "Two-way"
    elsif outgoing_count.positive?
      "You replied only"
    elsif incoming_count.positive?
      "They replied only"
    else
      "No observed replies"
    end
  end

  def follow_state(graph = Follow::Graph.latest)
    graph.state_for(self)
  end

  def timeline
    Timeline.new(self)
  end

  def last_interaction_at
    reply_events.loaded? ? reply_events.map(&:occurred_at).max : reply_events.maximum(:occurred_at)
  end

  def interactions
    @interactions ||= Interactions.for(self)
  end

  def avatar_image_url
    avatar_url&.sub(/_normal(\.\w+)\z/, "_bigger\\1")
  end

  # X serves banners at fixed sizes; cards use 600x200, the profile header 1500x500.
  def banner_image_url(size = "1500x500")
    "#{banner_url}/#{size}" if banner_url.present?
  end

  def profile_url
    "https://x.com/#{handle}"
  end

  def initials
    name.split.first(2).map { |part| part.first }.join.upcase
  end

  CLEANUP_QUIET_PERIOD = 60.days

  # Non-mutual, unprotected accounts with no observed interaction of any kind within the quiet period.
  # Someone with an older interaction is "quiet", never "no interaction".
  def self.cleanup_candidates(quiet_for: CLEANUP_QUIET_PERIOD)
    following = Follow::Snapshot.latest_complete("following")
    followers = Follow::Snapshot.latest("followers")
    return none unless following && followers&.fresh?

    eligible = where(id: following.person_ids)
      .where.not(id: followers.person_ids)
      .where.not(id: Follow::Protection.select(:person_id))
      .where.not(id: Follow::Review.where(reviewed_on: Date.current).select(:person_id))
    since = quiet_for.ago
    active = Interactions.index(eligible).reject { |_, interactions| interactions.quiet_since?(since) }.keys
    eligible.where.not(id: active).alphabetical
  end
end
