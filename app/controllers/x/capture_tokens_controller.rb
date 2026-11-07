class X::CaptureTokensController < ApplicationController
  # Renders the new token directly instead of redirecting, so it never sits in the session cookie.
  def create
    @token = Current.workspace.issue_token!(:capture)
    render :show
  end

  def destroy
    Current.workspace.revoke_token!(:capture)
    redirect_to x_sources_path(anchor: "capture"), notice: "Capture token revoked. The extension can no longer send data."
  end
end
