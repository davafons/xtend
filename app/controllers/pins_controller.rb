class PinsController < ApplicationController
  def create
    person = Person.find(params[:person_id])
    person.create_pin! unless person.pin
    redirect_back fallback_location: person_path(person), notice: "Person pinned."
  end

  def destroy
    person = Person.find(params[:person_id])
    person.pin&.destroy!
    redirect_back fallback_location: person_path(person), notice: "Pin removed."
  end
end
