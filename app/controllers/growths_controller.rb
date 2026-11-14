# The growth plan: goal and pace, this week's checkpoints and checklist, and your circle.
class GrowthsController < ApplicationController
  def show
    @growth = Outreach::Growth.new
    @week = (params[:week].presence&.to_i || @growth.current_week).clamp(1, Outreach::Growth::WEEKS) if @growth.started?
  end

  # Starts the plan (or changes its goal); restarting begins week 1 today from your follower count now.
  def update
    growth = Outreach::Growth.new
    attributes = { growth_goal: params.require(:growth).fetch(:goal).to_i }
    if params[:growth][:restart].present? || !growth.started?
      attributes.merge!(growth_started_on: Date.current, growth_start_followers: growth.followers)
      Outreach::GrowthCheck.delete_all
    end
    if attributes[:growth_goal] <= (attributes[:growth_start_followers] || growth.start_followers)
      redirect_to growth_path, alert: "Set a goal above your follower count."
    else
      Current.workspace.update!(attributes)
      redirect_to growth_path, notice: "Growth plan saved."
    end
  end
end
