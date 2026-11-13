# Dynamic client registration (RFC 7591), so an AI assistant can link by URL alone. Anyone may register, but a
# registration grants nothing: the owner still has to sign in and approve it, and unapproved ones are pruned.
class Oauth::RegistrationsController < ActionController::API
  rate_limit to: 10, within: 1.hour, store: RATE_LIMIT_STORE, by: -> { request.remote_ip },
    with: -> { render json: { error: "slow_down", error_description: "Too many registrations." }, status: :too_many_requests }

  def create
    Oauth::Client.prune!
    unless params[:token_endpoint_auth_method].in?([ nil, "none" ])
      return render json: { error: "invalid_client_metadata", error_description: "Only public clients (token_endpoint_auth_method none) are supported." }, status: :bad_request
    end
    client = Oauth::Client.register!(name: params[:client_name].to_s, redirect_uris: params[:redirect_uris])
    render status: :created, json: {
      client_id: client.client_id, client_id_issued_at: client.created_at.to_i, client_name: client.name,
      redirect_uris: client.redirect_uris, grant_types: %w[authorization_code refresh_token], response_types: %w[code],
      token_endpoint_auth_method: "none", scope: "mcp"
    }
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: "invalid_redirect_uri", error_description: error.record.errors.full_messages.to_sentence }, status: :bad_request
  end
end
