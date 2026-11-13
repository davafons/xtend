class Mcp::TokensController < ApplicationController
  # Renders the new token directly instead of redirecting, so it never sits in the session cookie.
  def create
    @token = Current.workspace.issue_mcp_token!
    render :show
  end

  def destroy
    Current.workspace.revoke_mcp_token!
    redirect_to ai_connector_path, notice: "Connector token revoked. MCP clients using it are now refused."
  end
end
