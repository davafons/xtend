# The browser extension's endpoints under /x/captures: no browser session or CSRF check, only the extension's OAuth
# link (or a pasted capture token), and only from a browser extension's origin.
module ExtensionAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :reject_web_origin, :authenticate_extension
  end

  private

  # The extension's background worker sends a chrome-extension:// origin. A web page must not reach these endpoints.
  def reject_web_origin
    origin = request.headers["Origin"]
    head :forbidden if origin.present? && !origin.match?(%r{\A(chrome|moz)-extension://[\w-]+\z})
  end

  def authenticate_extension
    grant = Oauth::Grant.authenticate(request.authorization.to_s[/\ABearer (\S+)\z/, 1], scope: "capture")
    return render(json: { error: "Missing or invalid capture token." }, status: :unauthorized) unless grant
    Current.workspace = grant.workspace
  end
end
