class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, store: RATE_LIMIT_STORE, with: -> { redirect_to new_session_path, alert: "Too many sign-in attempts. Try again in a few minutes." }

  def new
    redirect_to root_path if authenticated?
  end

  def create
    if user = User.authenticate_by(email_address: params[:email_address].to_s, password: params[:password].to_s)
      return_to = after_authentication_url
      start_new_session_for user
      redirect_to return_to
    else
      redirect_to new_session_path(email_address: params[:email_address]), alert: "That email address and password don't match."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
