# The network view: who interacts with whom among your people, from saved data only.
class NetworkController < ApplicationController
  def show
    @graph = Network::Graph.new(period: params[:period], scope: params[:scope], kinds: params[:kinds].presence || X::Interaction::KINDS,
      tag: params[:tag], include_owner: params[:me] != "0", outside: params[:outside] == "1")
    respond_to do |format|
      format.html do
        @coverage = Network::Coverage.new
        @tags = Tag.by_use.to_a
      end
      format.json { render json: @graph }
    end
  end
end
