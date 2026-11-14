# The weekly review: one page with the week's replies, what they brought, followers, best reply and post, and what
# to do next.
class WeeksController < ApplicationController
  def show
    @week = Network::Week.new(weeks_ago: params[:weeks_ago])
  end
end
