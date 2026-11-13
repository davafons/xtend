class InboxController < ApplicationController
  PERIODS = [ 7, 30, 90 ].freeze

  def show
    @days = PERIODS.include?(params[:days].to_i) ? params[:days].to_i : 30
    @follow_ups = params[:show] == "follow_ups"
    @inbox = ReplyInbox.new(days: @days, follow_ups: @follow_ups)
  end
end
