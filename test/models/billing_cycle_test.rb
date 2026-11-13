require "test_helper"

class BillingCycleTest < ActiveSupport::TestCase
  test "an ended cycle rolls into the next one with spend reset and pricing evidence kept" do
    X::BillingCycle.delete_all
    X::BillingCycle.create!(starts_on: Date.new(2026, 10, 12), ends_on: Date.new(2026, 11, 12), observed_at: 1.month.ago,
      provider_spend_micros: 7_300_000, pricing_evidence: "Console shows owned rates")

    travel_to Time.zone.local(2026, 12, 20, 9) do
      cycle = X::BillingCycle.current
      assert_equal [ Date.new(2026, 12, 12), Date.new(2027, 1, 12) ], [ cycle.starts_on, cycle.ends_on ]
      assert_equal 0, cycle.provider_spend_micros
      assert_equal "Console shows owned rates", cycle.pricing_evidence
      assert_equal 3, X::BillingCycle.count, "the skipped November–December cycle is recorded too"
      assert_equal cycle, X::BillingCycle.current
    end
  end

  test "with no recorded cycle there is nothing to roll and reads stay locked" do
    X::BillingCycle.delete_all
    assert_nil X::BillingCycle.current
  end

  test "reads no longer need a console observation from the last day" do
    cycle = X::BillingCycle.current
    cycle.update!(observed_at: 3.days.ago)
    assert cycle.reserve!(dataset: "followers", limit: 100)
  end
end
