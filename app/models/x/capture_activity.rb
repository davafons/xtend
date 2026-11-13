# What the browser extension has delivered lately, to check that it is working. Each batch that saved posts, likes,
# or bookmarks leaves capture sync runs that share one finished_at; batches that only refreshed accounts, follow
# states, or interactions leave none, so these counts are a floor. Contact of any kind, including the extension's
# empty connection test, shows in the capture grant's last use.
class X::CaptureActivity
  ACTIVE = 15.minutes
  Batch = Struct.new(:at, :counts)

  def initialize(workspace = Current.workspace, now: Time.current)
    @workspace = workspace
    @now = now
  end

  attr_reader :workspace

  # :working, :idle (connected but quiet), or :unconnected (not linked, or the extension never used its link).
  def state
    return :unconnected unless connected? && grants.filter_map(&:last_used_at).any?
    last_contact > @now - ACTIVE ? :working : :idle
  end

  def grants = @grants ||= workspace.oauth_grants.active.where(scope: "capture").to_a
  def connected? = grants.any?

  def last_contact = [ *grants.map(&:last_used_at), workspace.captured_at ].compact.max

  def recent_batches(limit = 10)
    runs.where(finished_at: ..@now).order(finished_at: :desc).limit(limit * 5).group_by(&:finished_at).first(limit).map do |at, batch|
      Batch.new(at, batch.each_with_object(Hash.new(0)) { |run, counts| counts[label(run)] += run.resource_count.to_i })
    end
  end

  def batch_count(since) = runs.where(finished_at: since..).distinct.count(:finished_at)
  def sightings(since) = X::PostObservation.where(observed_at: since..).count

  # Batches per day over the last days, oldest first, for the activity chart.
  def daily_batches(days = 14)
    first = @now.to_date - (days - 1)
    counts = runs.where(finished_at: first.beginning_of_day..).distinct.pluck(:finished_at).map(&:to_date).tally
    (first..@now.to_date).map { |day| [ day, counts.fetch(day, 0) ] }
  end

  private

  def runs = X::SyncRun.where(mode: "capture")

  def label(run)
    case run.dataset
    when "posts" then run.parameters&.dig("purpose") == "discovery" ? "feed post" : "context post"
    when "liked_posts" then "like"
    else "bookmark"
    end
  end
end
