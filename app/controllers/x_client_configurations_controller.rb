class XClientConfigurationsController < ApplicationController
  def update
    return head :forbidden unless request.local?
    return redirect_to(settings_path, alert: "Client configuration is disabled in the demo workspace.") if Rails.configuration.x.demo
    values = params.require(:x_client_configuration).permit(:client_id, :client_secret, :redirect_uri, :clear_client_secret).to_h.symbolize_keys
    XClientConfiguration.store!(values)
    session.delete(:x_oauth)
    redirect_to settings_path, notice: "Client configuration saved encrypted on this computer. The saved secret is never displayed."
  rescue XClientConfiguration::Connected, TokenVault::Unavailable => error
    redirect_to settings_path, alert: error.message
  rescue ActiveRecord::RecordInvalid => error
    redirect_to settings_path, alert: error.record.errors.full_messages.to_sentence
  end
end
