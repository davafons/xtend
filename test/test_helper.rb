ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  setup do
    Current.workspace = Workspace.create!(owner_x_id: "999")
    X::BillingCycle.create!(starts_on: Date.current, ends_on: Date.current + 30, observed_at: Time.current)
  end

  def profile(x_id: "101", handle: "builder", name: "A Builder")
    { x_id: x_id, handle: handle, name: name }
  end

  def ingest(x_id: "7001", target_x_id: "8001", direction: "outgoing", classification: "initial", occurred_at: 5.minutes.ago, person_profile: profile)
    ReplyEvent.ingest_verified!(profile: person_profile, x_id: x_id, target_x_id: target_x_id, direction: direction, classification: classification, source: "x_api", occurred_at: occurred_at, confirmed_at: Time.current)
  end

  def snapshot(direction, people, complete: true, observed_at: Time.current)
    record = Follow::Snapshot.create!(direction: direction, source: "x_api", observed_at: observed_at, completed_at: (observed_at if complete))
    people.each { |person| record.follow_memberships.create!(person: person) }
    record
  end
end

class ActionDispatch::IntegrationTest
  # Requests reset Current; restore the test's workspace so assertions after a request stay scoped.
  def process(...)
    workspace = Current.workspace
    super
  ensure
    Current.workspace = workspace
  end
end
