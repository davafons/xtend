# Who to engage with and which post to reply to now. Replies happen on X; the session counts them once confirmed.
class OutreachController < ApplicationController
  VIEWS = %w[posts people].freeze

  def show
    @view = VIEWS.include?(params[:view]) ? params[:view] : "posts"
    @session = Outreach::Session.current
    @prospects = Outreach::Prospects.new(reason: params[:reason])
    @openings = Outreach::Openings.new(@prospects)
    @all = params[:all] == "1"
    @today = @openings.today(@session.remaining)
    @due_reminders = Reminder.due.includes(:person).order(:due_on).to_a
    @upcoming_reminders = Reminder.upcoming.includes(:person).order(:due_on).limit(3).to_a
    @active_hours = Network::ActiveHours.new
  end
end
