# One saved post and the conversation Xtend collected around it.
class PostsController < ApplicationController
  def show
    @thread = Network::PostThread.new(params[:id])
  end
end
