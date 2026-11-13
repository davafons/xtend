# The preview card shown when hovering a person's name: an HTML fragment, loaded the first time it opens.
class People::CardsController < ApplicationController
  def show
    @person = Person.includes(:pin, :follow_protection, :tags, :reply_events).find(params[:person_id])
    render partial: "people/card", locals: { person: @person, graph: Follow::Graph.latest }
  end
end
