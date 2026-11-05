class Follow::FollowerPeriod < ApplicationRecord
  include WorkspaceScoped
  self.table_name = "follower_periods"
  belongs_to :person
  belongs_to :first_snapshot, class_name: "Follow::Snapshot"
  belongs_to :last_snapshot, class_name: "Follow::Snapshot"
  belongs_to :ended_snapshot, class_name: "Follow::Snapshot", optional: true
  scope :ongoing, -> { where(ended_by: nil) }
  scope :ended, -> { where.not(ended_by: nil) }
  scope :known_starts, -> { where.not(followed_after: nil) }

  def self.observe!(snapshot)
    return unless snapshot.direction == "followers" && snapshot.completed_at
    snapshot.with_lock do
      return if snapshot.follower_tracking_completed_at
      previous = Follow::Snapshot.where(direction: "followers").where.not(follower_tracking_completed_at: nil).order(observed_at: :desc, id: :desc).first
      raise ArgumentError, "Follower snapshots must be processed in observation order." if previous && snapshot.observed_at <= previous.observed_at
      members = snapshot.person_ids
      ongoing.where.not(person_id: members).find_each do |period|
        period.update!(ended_by: snapshot.completed_at, ended_snapshot: snapshot)
      end
      members.each do |person_id|
        period = ongoing.find_by(person_id: person_id)
        if period
          period.update!(last_seen_at: snapshot.observed_at, last_snapshot: snapshot)
        else
          create!(person_id: person_id, first_snapshot: snapshot, last_snapshot: snapshot,
            followed_after: previous&.observed_at, first_seen_at: snapshot.completed_at, last_seen_at: snapshot.observed_at)
        end
      end
      snapshot.update!(follower_tracking_completed_at: Time.current)
    end
  end

  def baseline?
    followed_after.nil?
  end

  def minimum_days
    [(last_seen_at - first_seen_at) / 1.day, 0].max
  end

  def maximum_days
    (ended_by - followed_after) / 1.day if followed_after && ended_by
  end

  def interaction_window(number, direction: nil)
    return if baseline?
    events = person.reply_events.where("occurred_at >= ?", first_seen_at)
    events = events.where("occurred_at <= ?", ended_by) if ended_by
    events = events.where(direction: direction) if direction
    time = events.order(:occurred_at, :x_id).offset(number - 1).pick(:occurred_at)
    return unless time
    { minimum_days: [(time - first_seen_at) / 1.day, 0].max,
      maximum_days: [(time - followed_after) / 1.day, 0].max,
      occurred_at: time }
  end

  def ambiguous_early_replies?
    followed_after && person.reply_events.where(occurred_at: followed_after...first_seen_at).exists?
  end

  def self.completed_duration_summary
    periods = ended.known_starts.to_a
    return if periods.empty?
    { count: periods.size, minimum_days: periods.sum(&:minimum_days) / periods.size,
      maximum_days: periods.sum(&:maximum_days) / periods.size, ongoing: ongoing.count, baseline: where(followed_after: nil).count }
  end
end
