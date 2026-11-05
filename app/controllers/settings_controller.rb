class SettingsController < ApplicationController
  def show
    @workspace = Current.workspace
    @cycle = X::BillingCycle.current
    @runs = X::SyncRun.order(created_at: :desc).limit(12)
    @followers = Follow::Snapshot.latest("followers")
    @following = Follow::Snapshot.latest("following")
  end

  def update
    @workspace = Current.workspace
    if @workspace.update(params.require(:workspace).permit(:name, :builder_interests, :monthly_budget_cents, :mcp_share_notes, :mcp_share_dms))
      redirect_to settings_path, notice: "Workspace settings saved."
    else
      @cycle = X::BillingCycle.current
    @runs = X::SyncRun.order(created_at: :desc).limit(12)
    @followers = Follow::Snapshot.latest("followers")
      @following = Follow::Snapshot.latest("following")
      render :show, status: :unprocessable_entity
    end
  end
end
