class PersonTagsController < ApplicationController
  before_action { @person = Person.find(params[:person_id]) }

  def create
    added = @person.add_tags!(params[:name])
    redirect_to @person, notice: added.any? ? "Tagged #{added.map(&:name).to_sentence}." : "No new tags to add."
  end

  def destroy
    @person.person_tags.find_by!(tag_id: params[:id]).destroy!
    redirect_to @person, notice: "Tag removed."
  end
end
