class X::ClientConfiguration < ApplicationRecord
  include WorkspaceScoped
  class Connected < StandardError; end
  PURPOSE = "x_oauth_client_configuration"

  def self.current
    first
  end

  def values
    JSON.parse(X::TokenVault.decrypt(settings_ciphertext, purpose: PURPOSE)).symbolize_keys
  end

  def self.store!(attributes)
    transaction do
      raise Connected, "Disconnect X locally before changing its client configuration." if X::Connection.exists?
      record = current || new
      previous = record.persisted? ? record.values : {}
      client_id = attributes.fetch(:client_id, "").to_s.strip
      redirect_uri = attributes.fetch(:redirect_uri, "").to_s.strip
      secret = attributes.fetch(:client_secret, "").to_s
      keep_secret = secret.blank? && attributes[:clear_client_secret] != "1" && previous[:client_id] == client_id
      secret = previous[:client_secret].to_s if keep_secret
      record.errors.add(:base, "Enter the OAuth Client ID.") if client_id.blank? || client_id.size > 500 || client_id.match?(/[\r\n]/)
      record.errors.add(:base, "Client Secret is too long.") if secret.size > 5000
      record.errors.add(:base, "Use an exact HTTPS callback URL ending in #{X::Config::CALLBACK_PATH}, without query or fragment. HTTP is allowed only for loopback.") unless redirect_uri.size <= 2000 && X::Config.valid_redirect_uri?(redirect_uri)
      raise ActiveRecord::RecordInvalid, record if record.errors.any?
      record.settings_ciphertext = X::TokenVault.encrypt({client_id: client_id, client_secret: secret, redirect_uri: redirect_uri}.to_json, purpose: PURPOSE)
      record.save!
      X::Authorization.where(consumed_at: nil).update_all(consumed_at: Time.current)
      record
    end
  end
end
