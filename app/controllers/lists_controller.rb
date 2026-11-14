# Your lists: the three tiers you move people through, and custom lists for any grouping you like.
class ListsController < ApplicationController
  before_action :set_list, only: %i[show update destroy]

  def index
    List.ensure_tiers!
    @lists = List.ordered.includes(:memberships).to_a
    @suggestions = Network::ListSuggestions.new
    @list = List.new
  end

  def show
    @people = @list.people.includes(:pin, :tags, :lists, :reply_events).order(Arel.sql("people.name COLLATE NOCASE")).to_a
    @tend = Network::Tend.new(list: @list).items.index_by { _1.person.id } if @list.cadence_days
    @latest = X::SourcePost.latest_by(@people.map(&:x_id))
    @graph = Follow::Graph.latest
  end

  def create
    @list = List.new(list_params)
    if @list.save
      redirect_to @list, notice: "List created."
    else
      redirect_to lists_path, alert: @list.errors.full_messages.to_sentence
    end
  end

  def update
    if @list.update(list_params)
      redirect_to @list, notice: "List saved."
    else
      redirect_to @list, alert: @list.errors.full_messages.to_sentence
    end
  end

  def destroy
    return redirect_to(@list, alert: "Tiers can't be deleted.") if @list.tier?
    @list.destroy!
    redirect_to lists_path, notice: "List deleted."
  end

  private

  def set_list
    @list = List.find(params[:id])
  end

  def list_params
    permitted = params.require(:list).permit(:name, :purpose, :cadence_days, :capacity)
    permitted.delete(:name) if @list&.tier?
    permitted.transform_values { _1.presence }
  end
end
