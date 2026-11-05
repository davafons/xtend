# Streamable HTTP endpoint for the MCP connector. Not a browser page, so it skips the browser and CSRF checks
# and authenticates every request with the owner's revocable bearer token instead.
class Mcp::EndpointsController < ActionController::API
  MAX_BYTES = 1.megabyte
  before_action :reject_foreign_origin, :authenticate

  def create
    body = request.raw_post
    return render(json: rpc_error(-32600, "Request too large."), status: :payload_too_large) if body.bytesize > MAX_BYTES
    message = JSON.parse(body)
    response = Mcp::Server.new.handle(message)
    response ? render(json: response) : head(:accepted)
  rescue JSON::ParserError
    render json: rpc_error(-32700, "Parse error."), status: :bad_request
  rescue StandardError => error
    Rails.error.report(error, handled: true)
    render json: rpc_error(-32603, "Internal error."), status: :internal_server_error
  end

  # This server never opens a server-initiated stream or keeps sessions.
  def unsupported
    response.headers["Allow"] = "POST"
    head :method_not_allowed
  end

  private

  # Browsers send Origin; a page on another site must not reach the connector (DNS rebinding protection).
  def reject_foreign_origin
    origin = request.headers["Origin"]
    head :forbidden if origin.present? && origin != request.base_url
  end

  def authenticate
    workspace = Workspace.current
    token = request.authorization.to_s[/\ABearer (\S+)\z/, 1]
    unless workspace.mcp_token_matches?(token)
      response.headers["WWW-Authenticate"] = 'Bearer realm="twitter-crm"'
      return render(json: rpc_error(-32001, "Missing or invalid connector token."), status: :unauthorized)
    end
    workspace.update_column(:mcp_token_used_at, Time.current) if workspace.mcp_token_used_at.nil? || workspace.mcp_token_used_at < 1.minute.ago
  end

  def rpc_error(code, message)
    { jsonrpc: "2.0", id: nil, error: { code: code, message: message } }
  end
end
