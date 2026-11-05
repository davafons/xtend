class X::Read < ApplicationRecord
  belongs_to :x_billing_cycle, class_name: "X::BillingCycle"
  belongs_to :x_sync_run, class_name: "X::SyncRun", optional: true
  validates :dataset, inclusion: { in: %w[identity followers following own_posts mentions users posts search liked_posts bookmarks dm_events] }
  validates :status, inclusion: { in: %w[reserved received committed uncertain] }
  validates :resource_limit, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1000 }

  def self.fetch!(dataset:, limit:, run: nil)
    raise X::BillingCycle::LimitExceeded, "Live X reads are disabled in the demo workspace." if Rails.configuration.x.demo
    cycle = X::BillingCycle.current || raise(X::BillingCycle::LimitExceeded, "Record the current X billing cycle and account spend before reading X.")
    read = cycle.reserve!(dataset: dataset, limit: limit, run: run)
    begin
      read.update!(dispatched_at: Time.current)
      payload = yield
      count = dataset == "identity" ? 1 : payload.fetch("data").size
      raise X::Client::Error, "X exceeded the reserved resource limit. Collection is paused." if count > limit
      rate = read.reserved_micros / limit
      read.update!(payload: payload, resource_count: count, estimated_micros: count * rate,
        received_at: Time.current, status: "received")
      read
    rescue StandardError => error
      read.update!(status: "uncertain", message: error.is_a?(X::Client::Error) ? error.message : "This request did not finish. Its reservation is retained.")
      raise
    end
  end

  def mark_applied!
    update!(status: "committed", committed_at: Time.current)
  end
end
