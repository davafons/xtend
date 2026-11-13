class InboxController < ApplicationController
  PERIODS = [ 7, 30, 90 ].freeze

  def show
    @days = PERIODS.include?(params[:days].to_i) ? params[:days].to_i : 30
    @inbox = ReplyInbox.new(days: @days)
  end
end
