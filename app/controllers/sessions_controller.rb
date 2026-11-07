# The sign-in page offers only "Sign in with X" (X::ConnectionsController). The fictional demo
# workspace can't call X, so there it opens the demo user directly.
class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]

  def new
    redirect_to root_path if authenticated?
  end

  def create
    return head(:not_found) unless Rails.configuration.x.demo && Rails.env.local?
    workspace = Workspace.first || Workspace.create!
    user = workspace.users.first || workspace.users.create!(x_handle: "demo")
    start_new_session_for user
    redirect_to root_path
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
