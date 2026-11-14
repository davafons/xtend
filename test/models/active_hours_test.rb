require "test_helper"

class ActiveHoursTest < ActiveSupport::TestCase
  test "an hour is busy or quiet against the four weeks of the impressions heatmap, in your time zone" do
    newest = Time.zone.local(2026, 11, 13, 23)
    start = newest - 4.weeks
    Enumerator.produce(start) { _1 + 1.hour }.take_while { _1 <= newest }.each do |hour|
      value = hour.hour == 23 ? 50 : (hour.hour.between?(2, 8) ? 0 : 5)
      X::AnalyticsHour.create!(metric: "Impressions", hour: hour, value: value, observed_at: newest)
    end
    hours = Network::ActiveHours.new(now: Time.zone.local(2026, 11, 14, 21, 30))

    assert_equal :busy, hours.level(Time.zone.local(2026, 11, 14, 23, 10))
    assert_equal :quiet, hours.level(Time.zone.local(2026, 11, 14, 4, 0))
    assert_equal Time.zone.local(2026, 11, 14, 23), hours.next_busy
    assert_not Network::ActiveHours.new(now: newest + 1.week).stale?
    assert Network::ActiveHours.new(now: newest + 3.weeks).stale?
  end

  test "without a heatmap there is no level, and Outreach says nothing about timing" do
    assert_nil Network::ActiveHours.new.level
    assert_not Network::ActiveHours.new.collected?
  end
end
