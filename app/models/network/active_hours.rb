# How busy each hour of the week usually is for your audience, from the impressions heatmap on X's analytics
# Audience page (X::AnalyticsHour): the four weeks before the newest collected hour, in your time zone. It tells
# whether now is one of your busier hours, and when the next one is.
class Network::ActiveHours
  WINDOW = 4.weeks
  METRIC = "Impressions"
  # An hour busier than three quarters of the week's hours counts as busy; one among the quietest quarter, quiet.
  SHARE = 0.25

  def initialize(now: Time.current)
    @now = now.in_time_zone
  end

  def collected? = slots.any?
  def newest = @newest ||= X::AnalyticsHour.where(metric: METRIC).maximum(:hour)
  def stale? = newest.nil? || newest < @now - 2.weeks

  # { [wday (0 = Monday), hour] => average impressions } over every slot in the window.
  def slots
    @slots ||= begin
      return {} unless newest
      rows = X::AnalyticsHour.where(metric: METRIC, hour: (newest - WINDOW)..newest).pluck(:hour, :value)
      rows.group_by { |hour, _| key(hour) }.transform_values { |values| values.sum(&:last).fdiv(values.size) }
    end
  end

  # :busy, :quiet, or :usual for a time, or nil without data.
  def level(time = @now)
    return unless collected?
    value = slots.fetch(key(time), 0)
    sorted = slots.values.sort
    return :busy if value.positive? && sorted.count { _1 < value } >= sorted.size * (1 - SHARE)
    return :quiet if value <= sorted[(sorted.size * SHARE).floor]
    :usual
  end

  # The start of the next busy hour within a day, or nil.
  def next_busy(from = @now)
    (1..24).map { |offset| (from + offset.hours).beginning_of_hour }.find { |time| level(time) == :busy }
  end

  private

  def key(time)
    local = time.in_time_zone
    [ (local.wday - 1) % 7, local.hour ]
  end
end
