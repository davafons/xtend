class DailySessionsController < ApplicationController
  def update
    DailySession.current.complete!
    redirect_to root_path, notice: "Twenty new conversations started. Your session is complete."
  rescue ActiveRecord::RecordInvalid
    redirect_to root_path, alert: "Your progress is saved. Complete 20 verified new targets to finish the session."
  end
end
