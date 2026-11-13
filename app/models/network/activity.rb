# Conversation activity over time, built from saved replies and DM metadata: what you sent, what came back, and
# who you talked with. An empty bucket means nothing was saved for that time, not that nothing happened.
# A period is a preset, or a custom from/to date range picked by dragging across a chart.
class Network::Activity
  PERIODS = {
    "30d" => { label: "30 days", span: 30.days, unit: :day },
    "90d" => { label: "90 days", span: 90.days, unit: :week },
    "1y" => { label: "Year", span: 1.year, unit: :week },
    "all" => { label: "All time", span: nil, unit: :month }
  }.freeze

  attr_reader :period, :range

  # range: a Date range, which takes precedence over period; it ends today at the latest.
  def initialize(period: nil, range: nil, now: Time.current)
    @now = now
    @range = range.first..[ range.last, now.to_date ].min if range && range.first <= now.to_date
    @period = if @range then "custom"
    elsif PERIODS.key?(period) then period
    else "90d"
    end
  end

  def custom?
    period == "custom"
  end

  # Days for a range up to about six weeks, weeks up to about nine months, months beyond.
  def unit
    return PERIODS.fetch(period)[:unit] unless custom?
    range.count <= 45 ? :day : range.count <= 270 ? :week : :month
  end

  def starts_at
    @starts_at ||= if custom? then range.first.in_time_zone
    elsif (span = PERIODS.fetch(period)[:span]) then @now - span
    else earliest || @now
    end
  end

  def ends_at
    custom? ? [ range.last.in_time_zone.end_of_day, @now ].min : @now
  end

  # The start of every bucket from the period's start to its end, including empty ones.
  def buckets
    @buckets ||= Enumerator.produce(bucket_for(starts_at)) { |bucket| bucket + 1.public_send(unit) }
      .take_while { |bucket| bucket <= ends_at }
  end

  # The first and last day a bucket covers inside the period.
  def bucket_dates(bucket)
    [ [ bucket, starts_at ].max.to_date, [ bucket.public_send(:"end_of_#{unit}"), ends_at ].min.to_date ]
  end

  def replies_sent = counts(replies.where(direction: "outgoing"))
  def replies_received = counts(replies.where(direction: "incoming"))
  def messages = counts(direct_messages)

  def empty?
    !replies.exists? && !direct_messages.exists?
  end

  # Distinct people you exchanged a reply or a DM with in the period, in either direction.
  def partner_count
    (Person.where(id: replies.select(:person_id)).pluck(:x_id) | direct_messages.distinct.pluck(:partner_x_id)).size
  end

  # People with replies or DMs going both ways in the period.
  def two_way_count
    reply_people = replies.group(:person_id).having("COUNT(DISTINCT direction) = 2").pluck(:person_id)
    dm_partners = direct_messages.group(:partner_x_id).having("COUNT(DISTINCT direction) = 2").pluck(:partner_x_id)
    (Person.where(id: reply_people).pluck(:x_id) | dm_partners).size
  end

  # The start of the bucket a time falls in.
  def bucket_for(time)
    time.in_time_zone.public_send(:"beginning_of_#{unit}")
  end

  private

  def replies
    ReplyEvent.where(occurred_at: starts_at..ends_at)
  end

  def direct_messages
    DirectMessage.where(occurred_at: starts_at..ends_at)
  end

  def earliest
    [ ReplyEvent.minimum(:occurred_at), DirectMessage.minimum(:occurred_at) ].compact.min
  end

  def counts(scope)
    tally = scope.pluck(:occurred_at).map { |time| bucket_for(time) }.tally
    buckets.map { |bucket| tally.fetch(bucket, 0) }
  end
end
