# How the follow cleanup is going: decisions per day and how many accounts you follow over time.
class Follow::Progress
  UNFOLLOWS = %w[unfollowed reported_unfollow].freeze

  def initialize(days: 30)
    @since = days.days.ago.to_date
  end

  # [date, unfollowed, kept] for every day since the first decision in the window, zeros included. An unfollow
  # you reported and the capture later saw counts once, on the first day.
  def decisions
    @decisions ||= begin
      reviews = Follow::Review.where(reviewed_on: @since..)
      unfollowed = reviews.where(decision: UNFOLLOWS).group(:person_id).minimum(:reviewed_on).values.tally
      kept = reviews.where(decision: "keep").group(:reviewed_on).count
      first = (unfollowed.keys + kept.keys).min
      first ? (first..Date.current).map { |day| [ day, unfollowed.fetch(day, 0), kept.fetch(day, 0) ] } : []
    end
  end

  # [time, count, source] for each complete following list, plus your profile's count when it is newer.
  # Between points the count is unknown.
  def following
    @following ||= begin
      lists = Follow::Snapshot.where(direction: "following").where.not(completed_at: nil).where(observed_at: @since..).order(:observed_at).to_a
      sizes = Follow::Membership.where(follow_snapshot_id: lists.map(&:id)).group(:follow_snapshot_id).count
      points = lists.map { |list| [ list.observed_at, sizes.fetch(list.id, 0), list.captured? ? "scrolled list" : "X API list" ] }
      workspace = Current.workspace
      if workspace.owner_following_count && workspace.owner_counts_seen_at && (points.empty? || workspace.owner_counts_seen_at > points.last.first)
        points << [ workspace.owner_counts_seen_at, workspace.owner_following_count, "your profile" ]
      end
      points
    end
  end

  def unfollowed_total = decisions.sum { |_, unfollowed, _| unfollowed }
  def kept_total = decisions.sum { |_, _, kept| kept }
end
