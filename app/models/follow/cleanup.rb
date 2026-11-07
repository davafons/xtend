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
  QUIET_PERIODS = [ 30, 60, 90, 180 ].freeze
  SORTS = {
    "reason" => "Best match first",
    "largest" => "Most followers",
    "smallest" => "Fewest followers",
    "name" => "Name"
  }.freeze

  attr_reader :reason, :inactive_days, :quiet_days, :sort

  def initialize(reason: nil, inactive_days: nil, quiet_days: nil, mutuals: nil, sort: nil)
    @reason = REASONS.key?(reason) ? reason : "inactive"
    @inactive_days = INACTIVE_PERIODS.include?(inactive_days.to_i) ? inactive_days.to_i : 180
    @quiet_days = QUIET_PERIODS.include?(quiet_days.to_i) ? quiet_days.to_i : Person::CLEANUP_QUIET_PERIOD.in_days.to_i
    @mutuals = mutuals.to_s != "0"
    @sort = SORTS.key?(sort) ? sort : "reason"
  end

  def mutuals? = @mutuals

  def following = @following ||= Follow::Snapshot.latest_complete("following")
  def followers = @followers ||= Follow::Snapshot.latest("followers")

  # Leaving mutuals out needs a fresh follower list; including them only labels them.
  def ready?
    following.present? && (mutuals? || followers&.fresh?)
  end

  def pool
    @pool ||= Person.cleanup_pool(mutuals: mutuals?).includes(:pin).to_a
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
    else people
    end
    people.first(limit)
  end

  def counts
    REASONS.keys.index_with { |key| matches(key).size }
  end

  # Follows whose last post is unknown: they can't appear as inactive until X reports one.
  def unknown_activity_count
    pool.count { |person| last_active[person.id].nil? }
  end
end
