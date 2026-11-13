ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

class ActiveSupport::TestCase
  setup do
    RATE_LIMIT_STORE.clear
    # New workspaces start with no interests; the ranking tests use a builder's.
    Current.workspace = Workspace.create!(owner_x_id: "999",
      builder_interests: "AI agents and coding tools\nBuilding and shipping Rails products\nDeveloper workflows")
    X::BillingCycle.create!(starts_on: Date.current, ends_on: Date.current + 30, observed_at: Time.current)
  end

  def profile(x_id: "101", handle: "builder", name: "A Builder")
    { x_id: x_id, handle: handle, name: name }
  end

  def ingest(x_id: "7001", target_x_id: "8001", direction: "outgoing", classification: "initial", occurred_at: 5.minutes.ago, person_profile: profile)
    ReplyEvent.ingest_verified!(profile: person_profile, x_id: x_id, target_x_id: target_x_id, direction: direction, classification: classification, source: "x_api", occurred_at: occurred_at, confirmed_at: Time.current)
  end

  # People cleanup would suggest for a reason, non-mutuals only: the quiet ones by default.
  def cleanup_ids(reason = "quiet", quiet_days: 60)
    Follow::Cleanup.new(reason: reason, quiet_days: quiet_days, mutuals: "0").matches.map(&:id)
  end

  def snapshot(direction, people, complete: true, observed_at: Time.current)
    record = Follow::Snapshot.create!(direction: direction, source: "x_api", observed_at: observed_at, completed_at: (observed_at if complete))
    people.each { |person| record.follow_memberships.create!(person: person) }
    record
  end
end

class ActionDispatch::IntegrationTest
  setup do
    @user = Current.workspace.users.create!(x_handle: "owner", x_user_id: "999")
    sign_in_as(@user)
  end

  # Requests reset Current; restore the test's workspace so assertions after a request stay scoped.
  def process(...)
    workspace = Current.workspace
    super
  ensure
    Current.workspace = workspace
  end
end
