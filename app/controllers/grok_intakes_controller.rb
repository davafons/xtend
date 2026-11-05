class GrokIntakesController < ApplicationController
  def create
    result = GrokIntake.new(via: "paste").call(GrokIntake.parse_paste(params[:grok_output]))
    counts = result.except(:run_id).values.flatten.group_by { |item| item[:status] }.transform_values(&:size)
    summary = counts.map { |status, count| "#{count} #{status.humanize(capitalize: false)}" }.join(", ")
    redirect_to settings_path(anchor: "discovery"), notice: "Grok results: #{summary.presence || 'nothing to import'}. No X API reads were made."
  rescue GrokIntake::Invalid => error
    redirect_to settings_path(anchor: "discovery"), alert: error.message
  end
end
