class Follow::TrialsController < ApplicationController
  def index
    @trials = Follow::Trials.new(days: params[:days], view: params[:view])
  end
end
