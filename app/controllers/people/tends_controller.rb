# Tend: who in your lists is due a reply, with the post to reply to.
class People::TendsController < ApplicationController
  def show
    @lists = List.ordered.where.not(cadence_days: nil).to_a
    @list = @lists.find { _1.id.to_s == params[:list] }
    @tend = Network::Tend.new(list: @list)
  end
end
