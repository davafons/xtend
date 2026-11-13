# The approval page. A client sends the owner here (behind Cloudflare Access and Sign in with X); approving sends a
# one-time code back to the client's registered redirect URI. Problems with the client or its redirect URI show
# here, since they can't safely be sent anywhere; everything else goes back to the client as an OAuth error.
class Oauth::AuthorizationsController < ApplicationController
  before_action :load_request
  # Approving redirects to the client's own site, so the form may submit there.
  content_security_policy do |policy|
    origin = URI.parse(@redirect_uri).then { |uri| "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}" } rescue nil
    policy.form_action(*policy.directives.fetch("form-action", []), origin) if origin
  end

  def new
  end

  def create
    if params[:decision] == "approve"
      code = Oauth::AuthorizationCode.issue!(workspace: Current.workspace, user: Current.user, client: @client,
        redirect_uri: @redirect_uri, code_challenge: params[:code_challenge], scope: @scope)
      redirect_to back_to_client(code: code.raw_code), allow_other_host: true
    else
      redirect_to back_to_client(error: "access_denied"), allow_other_host: true
    end
  end

  private

  def load_request
    @client = Oauth::Client.lookup(params[:client_id])
    @redirect_uri = params[:redirect_uri].to_s
    return render(:invalid, status: :bad_request) unless @client&.allows_redirect?(@redirect_uri)

    @scope = @client.scope_for(params[:scope])
    if params[:response_type] != "code"
      redirect_to back_to_client(error: "unsupported_response_type"), allow_other_host: true
    elsif params[:code_challenge_method] != "S256" || !params[:code_challenge].to_s.match?(/\A[A-Za-z0-9_-]{43}\z/)
      redirect_to back_to_client(error: "invalid_request", error_description: "PKCE with S256 is required."), allow_other_host: true
    elsif @scope.nil?
      redirect_to back_to_client(error: "invalid_scope"), allow_other_host: true
    elsif !Oauth::Resource.new(request).matches?(@scope, params[:resource])
      redirect_to back_to_client(error: "invalid_target"), allow_other_host: true
    end
  end

  def back_to_client(**query)
    uri = URI.parse(@redirect_uri)
    pairs = URI.decode_www_form(uri.query.to_s) + query.merge(state: params[:state].presence, iss: Oauth::Resource.new(request).issuer).compact.map { |key, value| [ key.to_s, value ] }
    uri.query = URI.encode_www_form(pairs)
    uri.to_s
  end
end
