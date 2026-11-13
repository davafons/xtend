# Connected apps: the owner revokes a link, or makes a token to paste into a client that can't do OAuth.
class Oauth::GrantsController < ApplicationController
  # Renders the token directly instead of redirecting, so it never sits in the session cookie.
  def create
    scope = params.require(:scope)
    return head(:unprocessable_entity) unless scope.in?(Oauth::Grant::SCOPES)
    @grant, @token = Oauth::Grant.paste!(workspace: Current.workspace, user: Current.user, scope: scope)
    response.headers["Cache-Control"] = "no-store"
    render :show
  end

  def destroy
    grant = Current.workspace.oauth_grants.find(params[:id])
    grant.revoke!
    redirect_back_or_to root_path, notice: "#{grant.client_name} disconnected. Its tokens no longer work."
  end
end
