require "uri"

# An app that can be linked to a workspace. First-party clients are known in advance: the browser extension and
# pasted tokens. AI clients register themselves (RFC 7591) when added to an assistant by URL; they are public
# clients, limited to the MCP scope, and only become linked when the owner approves them.
class Oauth::Client < ApplicationRecord
  EXTENSION = "xtend-capture".freeze
  PASTED = "xtend-pasted-token".freeze
  # The extension's manifest key fixes its ID, so only it can receive codes for this client; any other extension
  # in the browser gets its own chromiumapp.org host and is refused.
  EXTENSION_ID = "mlbeocefhmhknhobkkkhnlkamdoojjpi".freeze
  FIRST_PARTY = {
    EXTENSION => { name: "Xtend Capture extension", redirect_uris: [ "https://#{EXTENSION_ID}.chromiumapp.org/oauth" ],
      scopes: %w[capture], redirect_uri_pattern: nil },
    PASTED => { name: "Pasted token", redirect_uris: [], scopes: %w[mcp capture], redirect_uri_pattern: nil }
  }.freeze
  MAX_REDIRECT_URIS = 5
  UNUSED_REGISTRATION_LIFETIME = 1.day

  has_many :grants, class_name: "Oauth::Grant", foreign_key: :oauth_client_id, dependent: :destroy
  has_many :authorization_codes, class_name: "Oauth::AuthorizationCode", foreign_key: :oauth_client_id, dependent: :delete_all

  normalizes :name, with: ->(name) { name.to_s.squish.first(80) }
  validates :client_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :registered_via, inclusion: { in: %w[first_party dynamic] }
  validate :redirect_uris_are_safe

  scope :dynamic, -> { where(registered_via: "dynamic") }

  def self.first_party(client_id)
    client = find_or_initialize_by(client_id: client_id)
    client.assign_attributes(FIRST_PARTY.fetch(client_id))
    client.tap { |record| record.save! if record.changed? }
  end

  # First-party clients exist from their first use, so a fresh database needs no seeding, and their settings
  # follow the code: changing FIRST_PARTY updates the row on its next use.
  def self.lookup(client_id)
    client_id = client_id.to_s
    FIRST_PARTY.key?(client_id) ? first_party(client_id) : find_by(client_id: client_id)
  end

  def self.register!(name:, redirect_uris:)
    create!(client_id: "xtend_client_#{SecureRandom.hex(12)}", name: name.presence || "AI assistant",
      redirect_uris: Array(redirect_uris).map(&:to_s), scopes: %w[mcp], registered_via: "dynamic")
  end

  # Self-registered clients that were never approved are dropped after a day, so registration can't pile up rows.
  def self.prune!
    dynamic.where(created_at: ...UNUSED_REGISTRATION_LIFETIME.ago).where.missing(:grants).destroy_all
  end

  def dynamic? = registered_via == "dynamic"

  def allows_redirect?(uri)
    parsed = parse(uri)
    return false unless parsed && safe?(parsed)
    redirect_uris.include?(uri.to_s) || (redirect_uri_pattern.present? && parsed.host.to_s.match?(/\A(?:#{redirect_uri_pattern})\z/))
  end

  def allows_scope?(scope) = scopes.include?(scope)

  # The single scope this client may ask for; requests that name nothing get it.
  def scope_for(requested)
    requested = requested.to_s.split
    candidates = requested.empty? ? scopes : requested & scopes
    candidates.first if candidates.size == 1
  end

  private

  # HTTPS, or http on loopback for a client running on the owner's own machine (RFC 8252). No fragments.
  def safe?(parsed)
    return false if parsed.fragment || parsed.userinfo || parsed.host.blank?
    parsed.is_a?(URI::HTTPS) || (parsed.is_a?(URI::HTTP) && %w[localhost 127.0.0.1 [::1]].include?(parsed.host))
  end

  def parse(uri)
    URI.parse(uri.to_s)
  rescue URI::InvalidURIError
    nil
  end

  def redirect_uris_are_safe
    return unless dynamic?
    errors.add(:redirect_uris, "must list 1 to #{MAX_REDIRECT_URIS} URIs") unless redirect_uris.size.between?(1, MAX_REDIRECT_URIS)
    errors.add(:redirect_uris, "must be HTTPS, or http on localhost, without a fragment") unless redirect_uris.all? { |uri| (parsed = parse(uri)) && safe?(parsed) }
  end
end
