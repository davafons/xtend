class XConnectionsController < ApplicationController
  before_action :disable_caching

  def create
    return redirect_to(settings_path, alert: "Configure the X client ID and exact callback URL locally first.") unless XConfig.configured?
    return redirect_to(settings_path, alert: "Open this app at #{XConfig.callback_origin} before connecting, so the callback returns to the same browser session.") unless request.base_url == XConfig.callback_origin
    return redirect_to(settings_path, alert: "Live X authorization is disabled in the demo workspace.") if Rails.configuration.x.demo

    attempt, state = XAuthorization.start!
    verifier = SecureRandom.urlsafe_base64(64)
    session[:x_oauth] = { id: attempt.id, verifier: verifier, client_id: XConfig.client_id, redirect_uri: XConfig.redirect_uri, configuration_digest: XConfig.fingerprint }
    redirect_to XClient.new.authorization_url(state: state, verifier: verifier), allow_other_host: true
  end

  def callback
    attempt = session.delete(:x_oauth)&.symbolize_keys
    unless attempt && XAuthorization.consume!(attempt[:id], params[:state]) && attempt[:configuration_digest] == XConfig.fingerprint
      return redirect_to(settings_path, alert: "The X connection request expired or could not be verified. Start a new connection.")
    end
    return redirect_to(settings_path, alert: "X authorization was declined. Your existing connection is unchanged.") if params[:error].present?
    return redirect_to(settings_path, alert: "X did not return an authorization code. Try connecting again.") if params[:code].blank?

    client = XClient.new
    tokens = client.exchange(code: params[:code], verifier: attempt[:verifier], redirect_uri: attempt[:redirect_uri])
    identity = client.identity(tokens.fetch("access_token"))
    connection = XConnection.connect!(tokens, identity, configuration_digest: attempt[:configuration_digest])
    redirect_to settings_path, notice: "Connected @#{connection.username}. Identity verified; graph and discovery have not been collected."
  rescue XClient::Error, XConnection::AccountMismatch, TokenVault::Unavailable, XBillingCycle::LimitExceeded => error
    redirect_to settings_path, alert: error.message
  end

  def update
    connection = XConnection.current
    return redirect_to(settings_path, alert: "Connect X before checking its identity.") unless connection
    connection.check_identity!
    redirect_to settings_path, notice: "X identity checked. No follower, tweet, or search collection was run."
  rescue XClient::Error, XConnection::AccountMismatch, TokenVault::Unavailable, XBillingCycle::LimitExceeded => error
    redirect_to settings_path, alert: error.message
  end

  def destroy
    session.delete(:x_oauth)
    XAuthorization.where(consumed_at: nil).update_all(consumed_at: Time.current)
    XConnection.delete_all
    redirect_to settings_path, notice: "X credentials removed locally. Your CRM data remains. Revoke the app in X settings to remove the provider's authorization."
  end

  private

  def disable_caching
    response.set_header("Cache-Control", "no-store")
    response.set_header("Referrer-Policy", "no-referrer")
  end
end
