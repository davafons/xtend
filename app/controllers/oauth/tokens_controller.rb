# The token endpoint (RFC 6749) and revocation (RFC 7009), in the shapes off-the-shelf OAuth libraries expect.
# Clients are public: the code's PKCE verifier, or the refresh token itself, is what proves the caller.
class Oauth::TokensController < ActionController::API
  GRANT_TYPES = %w[authorization_code refresh_token].freeze
  rate_limit to: 60, within: 1.minute, store: RATE_LIMIT_STORE, by: -> { request.remote_ip },
    with: -> { oauth_error("slow_down", "Too many requests.", status: :too_many_requests) }
  before_action :no_store, :find_client

  def create
    case params[:grant_type]
    when "authorization_code" then exchange_code
    when "refresh_token" then refresh
    else oauth_error("unsupported_grant_type", "grant_type must be authorization_code or refresh_token.")
    end
  end

  # Always 200, as the RFC says, but only a token issued to this client ends anything.
  def revoke
    token = Oauth::Token.find_by_raw(params[:token])
    token.grant.revoke! if token && token.grant.client == @client && !token.grant.revoked?
    head :ok
  end

  private

  def no_store
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
  end

  def find_client
    @client = Oauth::Client.lookup(params[:client_id])
    oauth_error("invalid_client", "Unknown client_id.", status: :unauthorized) unless @client
  end

  def exchange_code
    code = Oauth::AuthorizationCode.find_by_code(params[:code])
    return oauth_error("invalid_grant", "Invalid or expired authorization code.") unless code && code.client == @client
    return oauth_error("invalid_grant", "redirect_uri doesn't match the authorization request.") unless params[:redirect_uri].to_s == code.redirect_uri
    return oauth_error("invalid_grant", "PKCE verification failed.") unless code.verifier_matches?(params[:code_verifier])
    return oauth_error("invalid_target", "resource doesn't match the authorization request.") unless resource.matches?(code.scope, params[:resource])
    code.with_lock do
      return oauth_error("invalid_grant", "Authorization code already used.") if code.consumed?
      code.update!(consumed_at: Time.current)
      grant, access, refresh, token = Oauth::Grant.link!(workspace: code.workspace, user: code.user, client: @client,
        scope: code.scope, user_agent: request.user_agent)
      render_tokens(grant, access, refresh, token)
    end
  end

  def refresh
    token = Oauth::Token.find_by_raw(params[:refresh_token])
    return oauth_error("invalid_grant", "Invalid refresh token.") unless token&.refresh? && token.grant.client == @client
    return oauth_error("invalid_target", "resource doesn't match the grant.") unless resource.matches?(token.grant.scope, params[:resource])
    access, refresh, issued = token.rotate!
    # Expired, revoked, or replayed: the link is over, and invalid_grant is how a client knows to reconnect.
    return oauth_error("invalid_grant", "Refresh token expired, revoked, or already used.") unless access
    render_tokens(token.grant, access, refresh, issued)
  end

  def render_tokens(grant, access, refresh, token)
    render json: { access_token: access, token_type: "Bearer", expires_in: (token.expires_at - Time.current).to_i,
      refresh_token: refresh, scope: grant.scope }
  end

  def oauth_error(error, description, status: :bad_request)
    render json: { error: error, error_description: description }, status: status
  end

  def resource = Oauth::Resource.new(request)
end
