class SettingsController < ApplicationController
  def show
    @workspace = Workspace.current
    @cycle = XBillingCycle.current
    @runs = XSyncRun.order(created_at: :desc).limit(12)
    @followers = FollowSnapshot.latest("followers")
    @following = FollowSnapshot.latest("following")
  end

  def update
    @workspace = Workspace.current
    if @workspace.update(params.require(:workspace).permit(:name, :builder_interests, :monthly_budget_cents, :mcp_share_notes, :mcp_share_dms))
      redirect_to settings_path, notice: "Workspace settings saved."
    else
      @cycle = XBillingCycle.current
    @runs = XSyncRun.order(created_at: :desc).limit(12)
    @followers = FollowSnapshot.latest("followers")
      @following = FollowSnapshot.latest("following")
      render :show, status: :unprocessable_entity
    end
  end
end
