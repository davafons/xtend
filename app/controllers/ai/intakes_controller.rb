class AI::IntakesController < ApplicationController
  def create
    result = AI::Intake.new(via: "paste").call(AI::Intake.parse_paste(params[:ai_output]))
    counts = result.except(:run_id).values.flatten.group_by { |item| item[:status] }.transform_values(&:size)
    summary = counts.map { |status, count| "#{count} #{status.humanize(capitalize: false)}" }.join(", ")
    redirect_to return_path, notice: "AI results: #{summary.presence || 'nothing to import'}. No X API reads were made."
  rescue AI::Intake::Invalid => error
    redirect_to return_path, alert: error.message
  end

  private

  def return_path
    return follow_reviews_path if params[:return_to] == "follow_reviews"
    ai_connector_path(anchor: params[:return_to] == "ai" ? "tags" : nil)
  end
end
