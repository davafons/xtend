# Signing in with X is the only way into the app, and it also connects the workspace's X data.
# Only allowed handles get in (`bin/rails users:allow`). Signing in again refreshes the tokens.
class X::ConnectionsController < ApplicationController
  allow_unauthenticated_access only: %i[ create callback ]
  rate_limit to: 10, within: 3.minutes, only: :create, store: RATE_LIMIT_STORE, with: -> { redirect_to new_session_path, alert: "Too many sign-in attempts. Try again in a few minutes." }
  before_action :disable_caching

  def create
    return redirect_back_with("The X app isn't configured on this server.") unless X::Config.configured?
    return redirect_back_with("Open this app at #{X::Config.callback_origin} to sign in, so X returns to the same browser session.") unless request.base_url == X::Config.callback_origin
    return redirect_back_with("Live X sign-in is disabled in the demo workspace.") if Rails.configuration.x.demo

    session[:return_to_after_authenticating] = settings_url if authenticated?
    state, verifier = SecureRandom.urlsafe_base64(32), SecureRandom.urlsafe_base64(64)
    session[:x_oauth] = { state: state, verifier: verifier, redirect_uri: X::Config.redirect_uri, configuration_digest: X::Config.fingerprint, expires_at: 10.minutes.from_now.to_i }
    redirect_to X::Client.new.authorization_url(state: state, verifier: verifier), allow_other_host: true
  end

  def callback
    attempt = session.delete(:x_oauth)&.symbolize_keys
    unless attempt && attempt[:expires_at].to_i > Time.current.to_i && ActiveSupport::SecurityUtils.secure_compare(attempt[:state].to_s, params[:state].to_s) && attempt[:configuration_digest] == X::Config.fingerprint
      return redirect_back_with("The X sign-in request expired or could not be verified. Try again.")
    end
    return redirect_back_with("X sign-in was cancelled.") if params[:error].present?
    return redirect_back_with("X did not return an authorization code. Try again.") if params[:code].blank?

    client = X::Client.new
    tokens = client.exchange(code: params[:code], verifier: attempt[:verifier], redirect_uri: attempt[:redirect_uri])
    payload = client.identity_payload(tokens.fetch("access_token"))
    identity = payload.fetch("data")
    user = User.for_x_identity(identity) or return redirect_back_with("@#{identity.fetch("username")} isn't allowed to sign in.")

    Current.workspace = user.workspace
    X::Read.record_sign_in!(payload)
    X::Connection.connect!(tokens, identity, configuration_digest: attempt[:configuration_digest])
    return_to = after_authentication_url
    start_new_session_for user
    redirect_to return_to
  rescue X::Client::Error, X::Connection::AccountMismatch, X::TokenVault::Unavailable => error
    redirect_back_with(error.message)
  end

  def update
    connection = X::Connection.current
    return redirect_to(settings_path, alert: "Sign in with X again to reconnect.") unless connection
    connection.check_identity!
    redirect_to settings_path, notice: "X identity checked. No follower, tweet, or search collection was run."
  rescue X::Client::Error, X::Connection::AccountMismatch, X::TokenVault::Unavailable, X::BillingCycle::LimitExceeded => error
    redirect_to settings_path, alert: error.message
  end

  def destroy
    session.delete(:x_oauth)
    X::Connection.delete_all
    redirect_to settings_path, notice: "X credentials removed. Your Xtend data remains. Sign in with X again to reconnect, or revoke the app in X settings to remove X's authorization."
  end

  private

  def redirect_back_with(alert)
    redirect_to authenticated? ? settings_path : new_session_path, alert: alert
  end

  def disable_caching
    response.set_header("Cache-Control", "no-store")
    response.set_header("Referrer-Policy", "no-referrer")
  end
end
