class Follow::ProtectionsController < ApplicationController
  def create
    person = Person.find(params[:person_id])
    person.create_follow_protection! unless person.follow_protection
    redirect_back fallback_location: person_path(person), notice: "Protected from cleanup."
  end

  def destroy
    person = Person.find(params[:person_id])
    person.follow_protection&.destroy!
    redirect_back fallback_location: person_path(person), notice: "Manual protection removed. Mutuals stay protected."
  end
end
