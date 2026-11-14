# The board: relationships as columns from strangers to your circle.
class People::BoardsController < ApplicationController
  def show
    @columns = Network::Pipeline.new.columns
  end
end
