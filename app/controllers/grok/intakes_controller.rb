class Grok::IntakesController < ApplicationController
  def create
    result = Grok::Intake.new(via: "paste").call(Grok::Intake.parse_paste(params[:grok_output]))
    counts = result.except(:run_id).values.flatten.group_by { |item| item[:status] }.transform_values(&:size)
    summary = counts.map { |status, count| "#{count} #{status.humanize(capitalize: false)}" }.join(", ")
    redirect_to return_path, notice: "Grok results: #{summary.presence || 'nothing to import'}. No X API reads were made."
  rescue Grok::Intake::Invalid => error
    redirect_to return_path, alert: error.message
  end

  private

  def return_path
    return follow_reviews_path if params[:return_to] == "follow_reviews"
    grok_connector_path(anchor: params[:return_to] == "grok" ? "tags" : nil)
  end
end
