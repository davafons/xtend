# Workspace interests, the X account connection, and the X developer app. Allowance and sharing toggles
# on other pages also save here and return to the page they came from.
class SettingsController < ApplicationController
  def show
    @workspace = Current.workspace
  end

  def update
    @workspace = Current.workspace
    if @workspace.update(params.require(:workspace).permit(:name, :builder_interests, :monthly_budget_cents, :mcp_share_notes, :mcp_share_dms))
      redirect_back_or_to settings_path, notice: "Workspace settings saved."
    else
      redirect_back_or_to settings_path, alert: @workspace.errors.full_messages.to_sentence
    end
  end
end
