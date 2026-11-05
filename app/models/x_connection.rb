class XConnection < ApplicationRecord
  class AccountMismatch < StandardError; end
  validates :x_user_id, :username, :token_ciphertext, :expires_at, :identity_checked_at, presence: true

  def self.current
    first
  end

  def self.connect!(tokens, identity, configuration_digest: nil)
    owner = Workspace.current
    if owner.owner_x_id.present? && owner.owner_x_id != identity.fetch("id")
      raise AccountMismatch, "This workspace belongs to another X account. Its existing data and connection have been preserved."
    end
    scope = tokens.fetch("scope", XConfig::SCOPES.join(" "))
    scope = scope.is_a?(String) ? scope.split : []
    unless XConfig::SCOPES.all? { |required| scope.include?(required) } && (scope - XConfig::SCOPES).empty?
      raise XClient::Error, "X did not grant exactly the requested read permissions. Reconnect with read-only access."
    end
    transaction do
      if configuration_digest && configuration_digest != XConfig.fingerprint
        raise XClient::Error, "Client configuration changed during authorization. Start a new connection."
      end
      connection = current || new
      connection.assign_attributes(x_user_id: identity.fetch("id"), username: identity.fetch("username"),
        granted_scopes: scope.join(" "), token_ciphertext: TokenVault.encrypt(tokens.slice("access_token", "refresh_token").to_json),
        expires_at: tokens.fetch("expires_in").to_i.seconds.from_now, identity_checked_at: Time.current)
      connection.save!
      owner.update!(owner_x_id: connection.x_user_id)
      connection
    end
  end

  def granted?(scope)
    granted_scopes.split.include?(scope)
  end

  def check_identity!
    identity = XClient.new.identity(access_token!)
    raise AccountMismatch, "X returned a different account. Reconnect the original account." unless identity.fetch("id") == x_user_id
    update!(username: identity.fetch("username"), identity_checked_at: Time.current)
  end

  def access_token!
    values = with_lock do
      values = tokens
      if expires_at <= 1.minute.from_now
        raise XClient::Error, "The X session expired without a refresh token. Reconnect X." if values["refresh_token"].blank?
        renewed = XClient.new.refresh(values.fetch("refresh_token"))
        scope = renewed.fetch("scope", granted_scopes)
        scope = scope.is_a?(String) ? scope.split : []
        raise XClient::Error, "X changed the granted permissions. Reconnect X." unless scope.sort == granted_scopes.split.sort
        renewed["refresh_token"] ||= values["refresh_token"]
        update!(token_ciphertext: TokenVault.encrypt(renewed.slice("access_token", "refresh_token").to_json), expires_at: renewed.fetch("expires_in").to_i.seconds.from_now)
        values = tokens
      end
      values
    end
    values.fetch("access_token")
  end

  def tokens
    JSON.parse(TokenVault.decrypt(token_ciphertext))
  end
  private :tokens
end
