class X::BillingCyclesController < ApplicationController
  def create
    values = params.require(:cycle)
    starts_on = Date.iso8601(values.fetch(:starts_on))
    ends_on = Date.iso8601(values.fetch(:ends_on))
    spend_cents = Integer(values.fetch(:spend_cents), 10)
    raise ArgumentError, "Use the current provider cycle dates and nonnegative spend in USD cents." unless starts_on <= Date.current && ends_on > Date.current && ends_on <= starts_on + 35 && spend_cents >= 0
    cycle = X::BillingCycle.find_by(starts_on: starts_on) || X::BillingCycle.new(starts_on: starts_on, ends_on: ends_on, observed_at: Time.current)
    raise ArgumentError, "Existing cycle dates cannot change after reads are recorded." if cycle.persisted? && cycle.ends_on != ends_on
    cycle.save!
    cycle.observe!(spend_cents: spend_cents)
    redirect_to settings_path(anchor: "billing"), notice: "X account spend observation saved. Other apps may consume the same account allowance."
  rescue ArgumentError, Date::Error, ActiveRecord::RecordInvalid, X::BillingCycle::LimitExceeded => error
    redirect_to settings_path(anchor: "billing"), alert: error.message
  end

  def update
    cycle = X::BillingCycle.find(params[:id])
    if params[:finish_trial] == "1"
      completed = X::SyncRun.where(dataset: %w[followers following own_posts mentions]).where("page_number > 0").distinct.pluck(:dataset)
      raise ArgumentError, "Collect a page from all four sample sources before finishing the trial." unless completed.sort == %w[followers following own_posts mentions].sort
      Workspace.current.update!(collection_trial_completed_at: Time.current)
      notice = "Collection trial reviewed. Future requests still respect the cycle allowance."
    else
      evidence = params[:pricing_evidence].to_s.strip
      raise ArgumentError, "Record billing evidence before selecting owned pricing." unless evidence.size.between?(10, 1000) && params[:owned_confirmed] == "1"
      cycle.update!(pricing_evidence: evidence, owned_configuration_digest: X::Config.fingerprint)
      notice = "Owned-pricing evidence recorded for the current developer app. Estimates remain separate from actual account billing."
    end
    redirect_to settings_path(anchor: "billing"), notice: notice
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to settings_path(anchor: "billing"), alert: error.message
  end
end
