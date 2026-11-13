# Receives x.com responses forwarded by the browser extension. Not a browser page: it skips the session and CSRF
# checks and authenticates each request with the extension's OAuth link, or a pasted capture token, instead.
class X::CapturesController < ActionController::API
  MAX_BYTES = 16.megabytes
  rate_limit to: 60, within: 1.minute, store: RATE_LIMIT_STORE, by: -> { request.remote_ip },
    with: -> { render json: { error: "Too many requests. Slow down." }, status: :too_many_requests }
  include ExtensionAuthentication

  def create
    return render(json: { error: "Batch too large." }, status: :payload_too_large) if request.raw_post.bytesize > MAX_BYTES
    batch = JSON.parse(request.raw_post)
    render json: X::Capture.ingest!(batch_key: batch["batch_key"], viewer_x_id: batch["viewer_x_id"], responses: batch["responses"])
  rescue JSON::ParserError, TypeError
    render json: { error: "Malformed batch." }, status: :bad_request
  rescue X::Capture::Rejected => error
    render json: { error: error.message }, status: :unprocessable_entity
  end
end
