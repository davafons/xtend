class X::ConnectionsController < ApplicationController
  before_action :disable_caching

  def create
    return redirect_to(settings_path, alert: "Configure the X client ID and exact callback URL locally first.") unless X::Config.configured?
    return redirect_to(settings_path, alert: "Open this app at #{X::Config.callback_origin} before connecting, so the callback returns to the same browser session.") unless request.base_url == X::Config.callback_origin
    return redirect_to(settings_path, alert: "Live X authorization is disabled in the demo workspace.") if Rails.configuration.x.demo

    attempt, state = X::Authorization.start!
    verifier = SecureRandom.urlsafe_base64(64)
    session[:x_oauth] = { id: attempt.id, verifier: verifier, client_id: X::Config.client_id, redirect_uri: X::Config.redirect_uri, configuration_digest: X::Config.fingerprint }
    redirect_to X::Client.new.authorization_url(state: state, verifier: verifier), allow_other_host: true
  end

  def callback
    attempt = session.delete(:x_oauth)&.symbolize_keys
    unless attempt && X::Authorization.consume!(attempt[:id], params[:state]) && attempt[:configuration_digest] == X::Config.fingerprint
      return redirect_to(settings_path, alert: "The X connection request expired or could not be verified. Start a new connection.")
    end
    return redirect_to(settings_path, alert: "X authorization was declined. Your existing connection is unchanged.") if params[:error].present?
    return redirect_to(settings_path, alert: "X did not return an authorization code. Try connecting again.") if params[:code].blank?

    client = X::Client.new
    tokens = client.exchange(code: params[:code], verifier: attempt[:verifier], redirect_uri: attempt[:redirect_uri])
    identity = client.identity(tokens.fetch("access_token"))
    connection = X::Connection.connect!(tokens, identity, configuration_digest: attempt[:configuration_digest])
    redirect_to settings_path, notice: "Connected @#{connection.username}. Identity verified; graph and discovery have not been collected."
  rescue X::Client::Error, X::Connection::AccountMismatch, X::TokenVault::Unavailable, X::BillingCycle::LimitExceeded => error
    redirect_to settings_path, alert: error.message
  end

  def update
    connection = X::Connection.current
    return redirect_to(settings_path, alert: "Connect X before checking its identity.") unless connection
    connection.check_identity!
    redirect_to settings_path, notice: "X identity checked. No follower, tweet, or search collection was run."
  rescue X::Client::Error, X::Connection::AccountMismatch, X::TokenVault::Unavailable, X::BillingCycle::LimitExceeded => error
    redirect_to settings_path, alert: error.message
  end

  def destroy
    session.delete(:x_oauth)
    X::Authorization.where(consumed_at: nil).update_all(consumed_at: Time.current)
    X::Connection.delete_all
    redirect_to settings_path, notice: "X credentials removed locally. Your CRM data remains. Revoke the app in X settings to remove the provider's authorization."
  end

  private

  def disable_caching
    response.set_header("Cache-Control", "no-store")
    response.set_header("Referrer-Policy", "no-referrer")
  end
end
