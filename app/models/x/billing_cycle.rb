class X::BillingCycle < ApplicationRecord
  include WorkspaceScoped
  class LimitExceeded < StandardError; end
  has_many :x_reads, class_name: "X::Read", foreign_key: :x_billing_cycle_id
  validates :starts_on, :ends_on, :observed_at, presence: true
  validates :provider_spend_micros, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate { errors.add(:ends_on, "must follow the start date") if starts_on && ends_on && ends_on <= starts_on }

  def self.current
    where("starts_on <= ? AND ends_on > ?", Date.current, Date.current).order(starts_on: :desc).first
  end

  def allowance_micros
    Current.workspace.monthly_budget_cents * 10_000
  end

  def pending_micros
    x_reads.where("id > ? OR status IN (?)", observed_through_read_id, %w[reserved uncertain]).sum("COALESCE(estimated_micros, reserved_micros)")
  end

  def remaining_micros
    [allowance_micros - provider_spend_micros - pending_micros, 0].max
  end

  def owned_pricing?
    pricing_evidence.present? && owned_configuration_digest.present? && owned_configuration_digest == X::Config.fingerprint
  end

  def observe!(spend_cents:)
    with_lock do
      raise LimitExceeded, "Wait for the active X request before recording spend." if X::Read.where(status: "reserved").exists?
      update!(provider_spend_micros: Integer(spend_cents) * 10_000,
        observed_at: Time.current, observed_through_read_id: x_reads.maximum(:id).to_i)
    end
  end

  def self.trial_remaining_micros
    [5_000_000 - X::Read.where(trial: true).sum("COALESCE(estimated_micros, reserved_micros)"), 0].max
  end

  def reserve!(dataset:, limit:, run: nil)
    with_lock do
      raise LimitExceeded, "Review the current X billing cycle on Spending before reading X." unless starts_on <= Date.current && ends_on > Date.current
      raise LimitExceeded, "Update the X console spend observation on Spending before collecting more data." if observed_at < 24.hours.ago
      basis = owned_pricing? && %w[followers following own_posts mentions liked_posts bookmarks].include?(dataset) ? "owned" : "standard"
      rate = basis == "owned" ? 1000 : (%w[own_posts mentions posts search liked_posts bookmarks].include?(dataset) ? 5000 : 10_000)
      reservation = limit * rate
      discovery = dataset == "search" || (dataset == "posts" && run&.parameters&.fetch("purpose", nil) == "discovery")
      if discovery && remaining_micros - reservation < allowance_micros / 5
        raise LimitExceeded, "New discovery is paused to preserve the final 20% for relationship updates. Use saved candidates."
      end
      trial = Current.workspace.collection_trial_completed_at.nil? && dataset != "identity"
      raise LimitExceeded, "This read exceeds the remaining local cycle allowance." if reservation > remaining_micros
      raise LimitExceeded, "This read exceeds the remaining $5 collection trial." if trial && reservation > self.class.trial_remaining_micros
      x_reads.create!(dataset: dataset, resource_limit: limit, reserved_micros: reservation,
        pricing_basis: basis, trial: trial, x_sync_run: run)
    end
  end
end
