# The one-time code the owner's approval sends back to the client, redeemed with its PKCE verifier for tokens.
class Oauth::AuthorizationCode < ApplicationRecord
  LIFETIME = 2.minutes

  belongs_to :workspace
  belongs_to :user
  belongs_to :client, class_name: "Oauth::Client", foreign_key: :oauth_client_id

  validates :redirect_uri, :code_challenge, :scope, presence: true

  attr_accessor :raw_code

  def self.issue!(**attributes)
    raw = SecureRandom.urlsafe_base64(32)
    create!(**attributes, code_digest: digest(raw), expires_at: LIFETIME.from_now).tap { |code| code.raw_code = raw }
  end

  def self.find_by_code(raw)
    raw.present? ? where(expires_at: Time.current..).find_by(code_digest: digest(raw)) : nil
  end

  def self.digest(raw) = Digest::SHA256.hexdigest(raw.to_s)

  # PKCE S256: the verifier the client kept must hash to the challenge it sent first.
  def verifier_matches?(verifier)
    return false unless verifier.to_s.match?(/\A[A-Za-z0-9._~-]{43,128}\z/)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier.to_s), padding: false)
    ActiveSupport::SecurityUtils.secure_compare(challenge, code_challenge)
  end

  def consumed? = consumed_at.present?
end
