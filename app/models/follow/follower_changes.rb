# Who started or stopped following you, newest first. Complete follower lists date each change to the window
# between two lists. Since the last complete list, x.com's own relationship fields on accounts you came across
# give an early sign, labeled as such until a complete list confirms it.
class Follow::FollowerChanges
  Change = Data.define(:person, :kind, :after, :by, :period) do
    def gained? = kind == :gained
  end
  Sighting = Data.define(:person, :kind, :seen_at) do
    def gained? = kind == :gained
  end

  def initialize(limit: 300)
    @limit = limit
  end

  def changes
    @changes ||= begin
      periods = Follow::FollowerPeriod.where.not(followed_after: nil).or(Follow::FollowerPeriod.ended)
        .includes(person: [ :reply_events, :follow_protection, :pin ]).to_a
      events = periods.flat_map do |period|
        [ (Change.new(period.person, :gained, period.followed_after, period.first_seen_at, period) if period.followed_after),
          (Change.new(period.person, :lost, period.last_seen_at, period.ended_by, period) if period.ended_by) ].compact
      end
      events.sort_by { |change| [ -change.by.to_f, change.person.name ] }.first(@limit)
    end
  end

  # Since the latest complete list: people x.com showed as following you who weren't on it, and people on it
  # x.com showed as not following you anymore.
  def sightings
    @sightings ||= begin
      list = Follow::Snapshot.latest_complete("followers")
      if list
        members = list.follow_memberships.select(:person_id)
        after = list.observed_at
        gained = Person.where(follows_you: true).where("follows_you_seen_at > ?", after).where.not(id: members)
        lost = Person.where(follows_you: false).where("follows_you_seen_at > ?", after).where(id: members)
        (gained.map { |person| Sighting.new(person, :gained, person.follows_you_seen_at) } +
          lost.map { |person| Sighting.new(person, :lost, person.follows_you_seen_at) }).sort_by { |sighting| -sighting.seen_at.to_f }
      else
        []
      end
    end
  end
end
