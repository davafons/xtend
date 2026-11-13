# The accounts you follow, sorted into the reasons you might stop following them. Activity comes from the
# latest post X reported for each account and from posts the capture saved; interactions from every
# collected channel. Neither proves a negative: unknown activity is never "inactive", and no collected
# interaction means none in the data you have, not none ever.
class Follow::Cleanup
  REASONS = {
    "inactive" => "Inactive",
    "strangers" => "Never interacted",
    "quiet" => "Quiet lately"
  }.freeze
  INACTIVE_PERIODS = [ 90, 180, 365 ].freeze
  QUIET_DAYS = 60
  QUIET_PERIODS = [ 30, 60, 90, 180 ].freeze
  SORTS = {
    "reason" => "Best match first",
    "largest" => "Most followers",
    "smallest" => "Fewest followers",
    "name" => "Name",
    "off_topic" => "Off-topic first"
  }.freeze

  attr_reader :reason, :inactive_days, :quiet_days, :sort, :tag

  def initialize(reason: nil, inactive_days: nil, quiet_days: nil, mutuals: nil, sort: nil, tag: nil)
    @reason = REASONS.key?(reason) ? reason : "inactive"
    @inactive_days = INACTIVE_PERIODS.include?(inactive_days.to_i) ? inactive_days.to_i : 180
    @quiet_days = QUIET_PERIODS.include?(quiet_days.to_i) ? quiet_days.to_i : QUIET_DAYS
    @mutuals = mutuals.to_s != "0"
    @sort = SORTS.key?(sort) ? sort : "reason"
    @tag = Tag.normalize(tag).presence
  end

  def mutuals? = @mutuals

  def following = @following ||= Follow::Snapshot.latest_complete("following")
  def followers = @followers ||= Follow::Snapshot.latest_complete("followers")

  # Leaving mutuals out needs a fresh follower list; including them only labels them.
  def ready?
    following.present? && (mutuals? || followers&.fresh?)
  end

  # With a tag, only people carrying it; "untagged" means people with no tags at all.
  def pool
    @pool ||= begin
      people = eligible
      people = tag == "untagged" ? people.untagged : people.tagged(tag) if tag
      people.includes(:pin, :tags).to_a
    end
  end

  # Tags carried by anyone in the unfiltered pool, most used first, for the filter menu.
  def tag_options
    Tag.joins(:person_tags).where(person_tags: { person_id: eligible.select(:id) })
      .group(:id).order(Arel.sql("COUNT(*) DESC"), :name).limit(40).pluck(:name)
  end

  # Accounts you follow that cleanup may suggest: never someone you chose to keep, or decided on today.
  # Mutuals are left out unless asked for, and leaving them out needs a fresh follower list, because a
  # stale one can't show that someone stopped following you.
  def eligible
    graph = Follow::Graph.latest
    return Person.none unless following && (mutuals? || graph.followers&.fresh?)

    people = Person.where(id: graph.following_ids_query)
      .where.not(id: Follow::Protection.select(:person_id))
      .where.not(id: Follow::Review.where(reviewed_on: Date.current).select(:person_id))
    mutuals? ? people : people.where.not(id: graph.follower_ids_query)
  end

  def interactions
    @interactions ||= Person::Interactions.index(pool)
  end

  # The latest known post per person: X's latest-post field or a post the capture saved, whichever is newer.
  def last_active
    @last_active ||= begin
      saved = X::SourcePost.where(author_x_id: pool.filter_map(&:x_id)).group(:author_x_id).maximum(:published_at)
      pool.to_h { |person| [ person.id, [ person.last_posted_at, saved[person.x_id] ].compact.max ] }
    end
  end

  def mutual?(person)
    (@graph ||= Follow::Graph.latest).follower?(person)
  end

  def matches(reason = self.reason)
    @matches ||= {}
    @matches[reason] ||= case reason
    when "inactive"
      cutoff = inactive_days.days.ago
      pool.select { |person| (at = last_active[person.id]) && at < cutoff }.sort_by { |person| [ last_active[person.id], person.id ] }
    when "strangers"
      pool.select { |person| interactions.fetch(person.id).latest.nil? }
        .sort_by { |person| [ last_active[person.id] ? 0 : 1, last_active[person.id].to_f, person.id ] }
    when "quiet"
      since = quiet_days.days.ago
      pool.select { |person| interactions.fetch(person.id).quiet_since?(since) }
        .sort_by { |person| (latest = interactions.fetch(person.id).latest) ? [ 1, latest.at.to_f, person.id ] : [ 0, 0, person.id ] }
    end
  end

  def candidates(limit)
    people = matches
    people = case sort
    when "largest" then people.sort_by { |person| [ person.followers_count ? 0 : 1, -person.followers_count.to_i, person.id ] }
    when "smallest" then people.sort_by { |person| [ person.followers_count ? 0 : 1, person.followers_count.to_i, person.id ] }
    when "name" then people.sort_by { |person| [ person.name.downcase, person.id ] }
    when "off_topic" then people.each_with_index.sort_by { |person, index| [ person.tags.any? { |t| t.name == AI::Classification::OFF_TOPIC } ? 0 : 1, index ] }.map(&:first)
    else people
    end
    people.first(limit)
  end

  # The latest posts the capture saved from each person, newest first, so a decision doesn't need a trip to X.
  # Reposts are left out: they show what someone shares, not what they write.
  def recent_posts(people, per_person: 2)
    ids = people.filter_map(&:x_id)
    return {} if ids.empty?
    ranked = X::SourcePost.where(author_x_id: ids, repost: false)
      .select("x_source_posts.*, ROW_NUMBER() OVER (PARTITION BY author_x_id ORDER BY published_at DESC) AS position")
    X::SourcePost.from(ranked, :x_source_posts).where("position <= ?", per_person).order(published_at: :desc).group_by(&:author_x_id)
  end

  def counts
    REASONS.keys.index_with { |key| matches(key).size }
  end

  # Follows whose last post is unknown: they can't appear as inactive until X reports one.
  def unknown_activity_count
    pool.count { |person| last_active[person.id].nil? }
  end
end
