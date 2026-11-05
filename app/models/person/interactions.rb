# The most recent observed interaction per channel for a set of people.
# Replies and mentions are public; likes and bookmarks have only a lower bound;
# DMs are one-to-one metadata. Nothing here proves that an interaction never happened.
class Person::Interactions
  Signal = Data.define(:channel, :at, :direction) do
    def approximate?
      %w[like bookmark].include?(channel)
    end
  end

  attr_reader :signals

  def self.index(people)
    rows = people.is_a?(ActiveRecord::Relation) ? people.pluck(:id, :x_id) : people.map { |person| [person.id, person.x_id] }
    ids = rows.map(&:first)
    x_ids = rows.map(&:last).compact
    signals = Hash.new { |hash, key| hash[key] = [] }
    person_by_x_id = rows.to_h { |id, x_id| [x_id, id] }

    ReplyEvent.where(person_id: ids).group(:person_id, :direction).maximum(:occurred_at).each do |(id, direction), at|
      signals[id] << Signal.new("reply", at, direction)
    end
    XSourcePost.joins(:x_sync_run).where(x_sync_runs: { dataset: "mentions" }, author_x_id: x_ids, repost: false)
      .group(:author_x_id).maximum(:published_at).each do |x_id, at|
      signals[person_by_x_id.fetch(x_id)] << Signal.new("mention", at, "incoming")
    end
    DirectMessage.where(partner_x_id: x_ids).group(:partner_x_id, :direction).maximum(:occurred_at).each do |(x_id, direction), at|
      signals[person_by_x_id.fetch(x_id)] << Signal.new("dm", at, direction)
    end
    Engagement.where(author_x_id: x_ids).group(:author_x_id, :kind)
      .maximum(Arel.sql("MAX(post_published_at, COALESCE(observed_after, post_published_at))")).each do |(x_id, kind), at|
      signals[person_by_x_id.fetch(x_id)] << Signal.new(kind, at.is_a?(String) ? Time.zone.parse("#{at} UTC") : at, "outgoing")
    end

    ids.index_with { |id| new(signals[id]) }
  end

  def self.for(person)
    index([person]).fetch(person.id)
  end

  def self.coverage
    public_since = XSourcePost.joins(:x_sync_run).where(x_sync_runs: { dataset: %w[own_posts mentions] }).minimum(:published_at)
    {
      "Replies and mentions" => public_since ? "since #{public_since.strftime('%-d %b %Y')}" : "not collected",
      "Likes" => engagement_coverage("like"),
      "Bookmarks" => engagement_coverage("bookmark"),
      "DMs" => dm_coverage
    }
  end

  def self.engagement_coverage(kind)
    coverage = Engagement.coverage(kind)
    return "not collected" unless coverage[:checked_at]
    coverage[:complete] ? "all X returns, checked #{coverage[:checked_at].strftime('%-d %b')}" : "recent pages only"
  end

  def self.dm_coverage
    since = DirectMessage.covered_since
    return "not collected" unless since
    archive = ArchiveImport.where(partial: false).maximum(:generated_at)
    latest_api = XSyncRun.where(dataset: "dm_events", status: "completed").maximum(:upper_bound)
    text = "since #{since.strftime('%-d %b %Y')}"
    return text unless archive
    later_api = latest_api && latest_api > archive
    text + " (archive through #{archive.strftime('%-d %b')}#{'; later API checks may miss encrypted chats' if later_api})"
  end
  private_class_method :engagement_coverage, :dm_coverage

  def initialize(signals)
    @signals = signals.sort_by { |signal| -signal.at.to_f }
  end

  def latest
    signals.first
  end

  def last(channel, direction: nil)
    signals.find { |signal| signal.channel == channel && (direction.nil? || signal.direction == direction) }
  end

  def quiet_since?(time)
    latest.nil? || latest.at < time
  end

  def awaiting_dm_reply?
    last("dm")&.direction == "incoming"
  end
end
