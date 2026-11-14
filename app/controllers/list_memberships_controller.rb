# Adding someone to a list or removing them. On a tier, adding moves them off any other tier.
class ListMembershipsController < ApplicationController
  before_action { @list = List.find(params[:list_id]) }

  def create
    person = find_or_create_person
    return redirect_back(fallback_location: @list, alert: "Enter an X handle.") unless person
    @list.add!(person)
    redirect_back fallback_location: @list, notice: "#{person.name} is on #{@list.name}."
  end

  def destroy
    person = Person.find(params[:id])
    @list.remove!(person)
    redirect_back fallback_location: @list, notice: "#{person.name} left #{@list.name}."
  end

  private

  # By person_id from a button, or by handle from the add field; an unknown handle becomes a bare person the
  # extension or an X read fills in later, as the Add person form does.
  def find_or_create_person
    return Person.find(params[:person_id]) if params[:person_id].present?
    handle = params[:handle].to_s.strip.delete_prefix("@").sub(%r{\Ahttps?://(www\.)?(x|twitter)\.com/}, "").split(%r{[/?]}).first.to_s.downcase
    return if handle.blank?
    Person.find_by(handle: handle) || Person.create(handle: handle, name: handle).then { _1 if _1.persisted? }
  end
end
