class Follow::Snapshot < ApplicationRecord
  include WorkspaceScoped
  has_many :follow_memberships, class_name: "Follow::Membership", foreign_key: :follow_snapshot_id, dependent: :destroy
  has_many :people, through: :follow_memberships
  validates :direction, inclusion: { in: %w[followers following] }
  validates :source, :observed_at, presence: true

  CAPTURE = "x_capture"

  # One page of your own Followers or Following list as x.com loaded it while you scrolled. A first page (no
  # cursor) starts a new list; every later page must start where the previous one ended, so a list only
  # completes when every page from the first to the last arrived. A page that doesn't continue an open list is
  # ignored, and an unfinished list never counts.
  def self.capture_page!(direction:, cursor:, people:, next_cursor:, last:, at:, expected: nil)
    open = where(direction: direction, source: CAPTURE, completed_at: nil)
    if cursor.blank?
      open.destroy_all
      snapshot = create!(direction: direction, source: CAPTURE, observed_at: at)
    else
      snapshot = open.where(next_cursor: cursor).order(:id).last
      return :unchained unless snapshot
    end
    people.each { |person| snapshot.follow_memberships.find_or_create_by!(person: person) }
    snapshot.update!(next_cursor: (next_cursor unless last), last_page_at: at, expected_count: expected || snapshot.expected_count)
    last ? snapshot.complete_capture! : :partial
  end

  # X's list can leave out a few suspended or deactivated accounts its count still includes, so a small gap is
  # tolerated; a bigger one means pages were missed and the list stays unfinished.
  def complete_capture!
    count = follow_memberships.count
    return :short if expected_count && count < expected_count - [ (expected_count * 0.05).ceil, 5 ].max
    update!(completed_at: last_page_at, next_cursor: nil)
    completed!
    :completed
  end

  # What a newly complete list settles: follower changes, or which reported unfollows happened.
  def completed!
    Follow::Review.confirm_unfollows!(self)
    Follow::FollowerPeriod.observe!(self) if direction == "followers"
  rescue ArgumentError
    # An older follower list than the last tracked one still serves as a snapshot; it just can't date changes.
  end

  def captured? = source == CAPTURE

  def self.latest_complete(direction)
    where(direction: direction).where.not(completed_at: nil).order(observed_at: :desc).first
  end

  # The newest list of either kind, finished or not, for showing collection progress.
  def self.latest(direction)
    where(direction: direction).order(observed_at: :desc, id: :desc).first
  end

  # An unfinished list you are scrolling right now.
  def self.capturing(direction)
    where(direction: direction, source: CAPTURE, completed_at: nil).where(last_page_at: 1.hour.ago..).order(:id).last
  end

  # [observed_at, follower count] for every follower check in a time range. An incomplete check has no count,
  # so a chart shows a gap there instead of a partial total.
  def self.follower_counts(since: nil, before: nil)
    snapshots = where(direction: "followers").order(:observed_at)
    snapshots = snapshots.where(observed_at: since..before) if since || before
    snapshots = snapshots.to_a
    counts = Follow::Membership.where(follow_snapshot_id: snapshots.select(&:completed_at).map(&:id)).group(:follow_snapshot_id).count
    snapshots.map { |snapshot| [ snapshot.observed_at, (counts.fetch(snapshot.id, 0) if snapshot.completed_at) ] }
  end

  # [observed_at, gained, lost] for each tracked follower check in a time range. The first tracked check is the
  # baseline, so its changes are unknown (nil) rather than zero.
  def self.follower_changes(since: nil, before: nil)
    checks = where(direction: "followers").where.not(follower_tracking_completed_at: nil).order(:observed_at, :id)
    baseline = checks.first
    checks = checks.where(observed_at: since..before) if since || before
    checks = checks.to_a
    gained = Follow::FollowerPeriod.known_starts.where(first_snapshot_id: checks.map(&:id)).group(:first_snapshot_id).count
    lost = Follow::FollowerPeriod.where(ended_snapshot_id: checks.map(&:id)).group(:ended_snapshot_id).count
    checks.map do |check|
      check == baseline ? [ check.observed_at, nil, nil ] : [ check.observed_at, gained.fetch(check.id, 0), lost.fetch(check.id, 0) ]
    end
  end

  # Complete, under a day old, and not followed by a failed or unfinished X API check. An unfinished scroll
  # through the list on x.com is only browsing, so it doesn't count against it.
  def fresh?
    completed_at.present? && observed_at >= 24.hours.ago &&
      !self.class.where(direction: direction, completed_at: nil).where.not(source: CAPTURE).where("observed_at > ?", observed_at).exists?
  end

  def person_ids
    follow_memberships.pluck(:person_id)
  end
end
