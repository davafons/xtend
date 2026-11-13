# People you started following since your first complete following list: when you followed them, whether they
# followed back, and what passed between you since. It supports following builders, talking with them for a few
# weeks, and then deciding: keep the ones who followed back or engage, unfollow the ones who didn't.
#
# Follow dates are ranges: between the last complete list without them and the first sighting with them (a later
# list, your follow click, or your Following page). Anyone already on the first list has an unknown start and is
# left out.
class Follow::Trials
  PERIODS = [ 14, 30, 60 ].freeze
  VIEWS = { "due" => "No follow-back yet", "followed_back" => "Followed back", "waiting" => "Still in trial", "all" => "All" }.freeze

  Trial = Data.define(:person, :after, :by, :follows_back, :back_since, :interactions, :kept) do
    def days = ((Time.current - by) / 1.day).floor
  end

  attr_reader :days, :view

  def initialize(days: nil, view: nil)
    @days = PERIODS.include?(days.to_i) ? days.to_i : 30
    @view = VIEWS.key?(view) ? view : "due"
  end

  def available? = baseline.present?

  def baseline
    @baseline ||= Follow::Snapshot.where(direction: "following").where.not(completed_at: nil).order(:observed_at, :id).first
  end

  def all
    @all ||= begin
      return [] unless baseline
      graph = Follow::Graph.latest
      lists = Follow::Snapshot.where(direction: "following").where.not(completed_at: nil).order(:observed_at).to_a
      baseline_ids = baseline.follow_memberships.pluck(:person_id).to_set
      people = Person.where(id: graph.following_ids.to_a - baseline_ids.to_a).includes(:follow_protection).to_a
      listed = Follow::Membership.where(follow_snapshot_id: lists.map(&:id), person_id: people.map(&:id))
        .joins(:follow_snapshot).group(:person_id).minimum("follow_snapshots.observed_at")
      owner = Current.workspace.owner_x_id
      clicked = X::FollowEdge.where(follower_x_id: owner, followed_x_id: people.filter_map(&:x_id)).pluck(:followed_x_id, :first_seen_at).to_h
      back = Follow::FollowerPeriod.ongoing.where(person_id: people.map(&:id)).group(:person_id).minimum(:first_seen_at)
      notified = X::FollowEdge.where(follower_x_id: people.filter_map(&:x_id), followed_x_id: owner).where.not(followed_at: nil).pluck(:follower_x_id, :followed_at).to_h
      interactions = Person::Interactions.index(people)
      unfollowed = Follow::Review.where(person_id: people.map(&:id), decision: Follow::Progress::UNFOLLOWS).group(:person_id).maximum(:reviewed_on)
      people.filter_map do |person|
        by = [ listed[person.id], clicked[person.x_id] ].compact.min
        next unless by && by > baseline.observed_at
        # You reported unfollowing them after this follow began; the capture or a list will confirm it.
        next if unfollowed[person.id] && unfollowed[person.id] >= by.to_date
        after = lists.reverse.find { |list| list.observed_at < by }&.observed_at || baseline.observed_at
        follows_back = graph.follower?(person)
        since = notified[person.x_id] || back[person.id] || (person.follows_you_seen_at if person.follows_you)
        Trial.new(person, after, by, follows_back, (since if follows_back), interactions.fetch(person.id), person.follow_protection.present?)
      end.sort_by { |trial| [ -trial.days, trial.person.name ] }
    end
  end

  def due = all.select { |trial| !trial.follows_back && !trial.kept && trial.days >= days }
  def followed_back = all.select(&:follows_back)
  def waiting = all.select { |trial| !trial.follows_back && trial.days < days }

  def list
    case view
    when "due" then due
    when "followed_back" then followed_back
    when "waiting" then waiting
    else all
    end
  end

  def counts
    { "due" => due.size, "followed_back" => followed_back.size, "waiting" => waiting.size, "all" => all.size }
  end
end
