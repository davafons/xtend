# The protected resources this server issues tokens for, one per scope: AI clients use the MCP endpoint, and the
# browser extension posts captures. A token for one is refused at the other.
class Oauth::Resource
  PATHS = { "mcp" => "/mcp", "capture" => "/x/captures" }.freeze
  METADATA_PATH = "/.well-known/oauth-protected-resource".freeze

  def initialize(request)
    @request = request
  end

  def issuer = Rails.configuration.x.oauth_issuer.presence || @request.base_url
  def url(scope) = "#{issuer}#{PATHS.fetch(scope)}"
  def metadata_url(scope) = "#{issuer}#{METADATA_PATH}#{PATHS.fetch(scope)}"

  # A client may name the resource it wants (RFC 8707); it has to be the one the scope protects.
  def matches?(scope, resource) = resource.blank? || resource.to_s.chomp("/") == url(scope)

  def scope_for(resource) = PATHS.keys.find { |scope| url(scope) == resource.to_s.chomp("/") }
end
