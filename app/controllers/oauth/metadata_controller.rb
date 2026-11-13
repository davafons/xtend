# Discovery (RFC 8414 and RFC 9728): how a client that only knows the MCP URL finds where to register, ask for
# approval, and get tokens. Served outside Cloudflare Access, like the endpoints it points to.
class Oauth::MetadataController < ActionController::API
  def authorization_server
    expires_in 1.hour, public: true
    issuer = resource.issuer
    render json: {
      issuer: issuer,
      authorization_endpoint: "#{issuer}#{oauth_authorize_path}",
      token_endpoint: "#{issuer}#{oauth_token_path}",
      revocation_endpoint: "#{issuer}#{oauth_revoke_path}",
      registration_endpoint: "#{issuer}#{oauth_register_path}",
      scopes_supported: Oauth::Grant::SCOPES,
      response_types_supported: %w[code],
      grant_types_supported: Oauth::TokensController::GRANT_TYPES,
      code_challenge_methods_supported: %w[S256],
      token_endpoint_auth_methods_supported: %w[none],
      revocation_endpoint_auth_methods_supported: %w[none],
      authorization_response_iss_parameter_supported: true
    }
  end

  # /.well-known/oauth-protected-resource/mcp describes /mcp and /.well-known/oauth-protected-resource/x/captures
  # describes captures; the bare path describes /mcp, for clients that look there first.
  def protected_resource
    scope = resource.scope_for("#{resource.issuer}/#{params[:resource]}") || "mcp"
    expires_in 1.hour, public: true
    render json: { resource: resource.url(scope), authorization_servers: [ resource.issuer ],
      scopes_supported: [ scope ], bearer_methods_supported: %w[header] }
  end

  private

  def resource = @resource ||= Oauth::Resource.new(request)
end
