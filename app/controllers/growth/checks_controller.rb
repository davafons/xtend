# Ticks and unticks the checklist items Xtend can't see for itself, such as "one story post".
class Growth::ChecksController < ApplicationController
  def create
    Outreach::GrowthCheck.find_or_create_by!(week: params.require(:week), key: params.require(:key))
    redirect_to growth_path(week: params[:week])
  end

  def destroy
    Outreach::GrowthCheck.where(week: params.require(:week), key: params.require(:key)).destroy_all
    redirect_to growth_path(week: params[:week])
  end
end
