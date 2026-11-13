# The signed-in user's theme. It's a personal preference, so it lives on the user, not the workspace.
class AppearancesController < ApplicationController
  def update
    Current.user.update!(theme: params.require(:theme))
    redirect_back_or_to root_path
  rescue ActiveRecord::RecordInvalid
    redirect_back_or_to root_path, alert: "That theme isn't available."
  end
end
