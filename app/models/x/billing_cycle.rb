class X::BillingCycle < ApplicationRecord
  include WorkspaceScoped
  class LimitExceeded < StandardError; end
  has_many :x_reads, class_name: "X::Read", foreign_key: :x_billing_cycle_id
  validates :starts_on, :ends_on, :observed_at, presence: true
  validates :provider_spend_micros, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate { errors.add(:ends_on, "must follow the start date") if starts_on && ends_on && ends_on <= starts_on }

  # The cycle covering today. Once a recorded cycle ends, the next one starts on its own: same day of the
  # month, spend back at zero as X resets it, and the same owned-pricing evidence. Local estimates, which run
  # above actual billing, keep counting against the allowance until you record a console observation.
  def self.current
    where("starts_on <= ? AND ends_on > ?", Date.current, Date.current).order(starts_on: :desc).first || roll_forward
  end

  def self.roll_forward
    last = order(starts_on: :desc).first or return
    transaction do
      while last.ends_on <= Date.current
        months = ((last.ends_on.year * 12 + last.ends_on.month) - (last.starts_on.year * 12 + last.starts_on.month)).clamp(1, 12)
        last = create!(starts_on: last.ends_on, ends_on: last.ends_on.advance(months: months), provider_spend_micros: 0,
          observed_at: Time.current, observed_through_read_id: X::Read.maximum(:id).to_i,
          pricing_evidence: last.pricing_evidence, owned_configuration_digest: last.owned_configuration_digest)
      end
    end
    last
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
      basis = owned_pricing? && %w[followers following own_posts mentions liked_posts bookmarks].include?(dataset) ? "owned" : "standard"
      rate = basis == "owned" ? 1000 : (%w[own_posts mentions posts liked_posts bookmarks].include?(dataset) ? 5000 : 10_000)
      reservation = limit * rate
      trial = Current.workspace.collection_trial_completed_at.nil? && dataset != "identity"
      raise LimitExceeded, "This read exceeds the remaining local cycle allowance." if reservation > remaining_micros
      raise LimitExceeded, "This read exceeds the remaining $5 collection trial." if trial && reservation > self.class.trial_remaining_micros
      x_reads.create!(dataset: dataset, resource_limit: limit, reserved_micros: reservation,
        pricing_basis: basis, trial: trial, x_sync_run: run)
    end
  end
end
