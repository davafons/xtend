class Mcp::TokensController < ApplicationController
  # Renders the new token directly instead of redirecting, so it never sits in the session cookie.
  def create
    @token = Workspace.current.issue_mcp_token!
    render :show
  end

  def destroy
    Workspace.current.revoke_mcp_token!
    redirect_to settings_path(anchor: "connector"), notice: "Connector token revoked. MCP clients using it are now refused."
  end
end
