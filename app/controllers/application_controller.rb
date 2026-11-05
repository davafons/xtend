class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Replaced by the signed-in user's workspace once authentication lands.
  before_action { Current.workspace = Workspace.first || Workspace.create! }
end
