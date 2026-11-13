# Who to engage with and which post to reply to now. Replies happen on X; the session counts them once confirmed.
class OutreachController < ApplicationController
  VIEWS = %w[posts people].freeze

  def show
    @view = VIEWS.include?(params[:view]) ? params[:view] : "posts"
    @session = Outreach::Session.current
    @prospects = Outreach::Prospects.new(reason: params[:reason])
    @openings = Outreach::Openings.new(@prospects)
  end
end
