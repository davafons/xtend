# An access or refresh token. Only a keyed digest is stored. The key is secret_key_base, as it was for the
# workspace tokens these replace, so their digests carried over and rotating the key ends every link.
class Oauth::Token < ApplicationRecord
  KINDS = %w[access refresh].freeze
  PREFIXES = { "access" => "xtend_at", "refresh" => "xtend_rt" }.freeze
  ACCESS_LIFETIME = 30.days
  REFRESH_LIFETIME = 90.days
  # A client that retries a refresh (a lost response, two tabs) gets fresh tokens instead of losing the link.
  REUSE_GRACE = 30.seconds

  belongs_to :grant, class_name: "Oauth::Grant", foreign_key: :oauth_grant_id

  validates :kind, inclusion: { in: KINDS }
  validates :token_digest, presence: true, uniqueness: true

  attr_accessor :raw_token

  def self.mint!(grant, kind:, expires_at: (kind == "access" ? ACCESS_LIFETIME : REFRESH_LIFETIME).from_now)
    raw = "#{PREFIXES.fetch(kind)}_#{SecureRandom.urlsafe_base64(32)}"
    create!(grant: grant, kind: kind, token_digest: digest(raw), expires_at: expires_at).tap { |token| token.raw_token = raw }
  end

  # Every Xtend token starts with xtend_, including the pasted ones from before OAuth.
  def self.find_by_raw(raw)
    return unless raw.to_s.start_with?("xtend_")
    find_by(token_digest: digest(raw))
  end

  def self.digest(raw) = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, raw.to_s)

  def access? = kind == "access"
  def refresh? = kind == "refresh"
  def usable? = consumed_at.nil? && (expires_at.nil? || expires_at.future?)

  # A refresh token works once (OAuth 2.1). Presented again after the grace period, it means someone else holds a
  # copy, so the whole grant is revoked. Returns the new raw access and refresh tokens, or nil.
  def rotate!
    return unless refresh?
    with_lock do
      return if expires_at.past? || grant.revoked?
      if consumed_at
        return grant.issue_tokens! if consumed_at > REUSE_GRACE.ago
        grant.revoke!
        return
      end
      update!(consumed_at: Time.current)
      grant.issue_tokens!
    end
  end
end
