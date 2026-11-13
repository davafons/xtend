# One app linked to one workspace for one scope: what the owner sees under connected apps and can revoke.
class Oauth::Grant < ApplicationRecord
  SCOPES = %w[mcp capture].freeze
  TOUCH_INTERVAL = 1.minute

  belongs_to :workspace
  belongs_to :user, optional: true
  belongs_to :client, class_name: "Oauth::Client", foreign_key: :oauth_client_id
  has_many :tokens, class_name: "Oauth::Token", foreign_key: :oauth_grant_id, dependent: :delete_all

  validates :scope, inclusion: { in: SCOPES }
  validate :client_allows_scope, on: :create

  scope :active, -> { where(revoked_at: nil) }
  scope :newest, -> { order(created_at: :desc) }

  delegate :name, to: :client, prefix: true

  # Linking through OAuth: a refreshable pair. Returns the grant and the raw access and refresh tokens.
  def self.link!(workspace:, user:, client:, scope:, user_agent: nil)
    grant = create!(workspace: workspace, user: user, client: client, scope: scope, user_agent: user_agent&.first(255))
    [ grant, *grant.issue_tokens! ]
  end

  # A token the owner copies into a client that can't do OAuth. It doesn't expire; revoking the grant ends it.
  def self.paste!(workspace:, user:, scope:)
    grant = create!(workspace: workspace, user: user, client: Oauth::Client.first_party(Oauth::Client::PASTED), scope: scope)
    [ grant, Oauth::Token.mint!(grant, kind: "access", expires_at: nil).raw_token ]
  end

  def self.authenticate(raw, scope:)
    token = Oauth::Token.find_by_raw(raw)
    grant = token&.grant
    return unless token&.access? && token.usable? && grant.scope == scope && !grant.revoked?
    grant.record_use!
    grant
  end

  def issue_tokens!
    access = Oauth::Token.mint!(self, kind: "access")
    refresh = Oauth::Token.mint!(self, kind: "refresh")
    [ access.raw_token, refresh.raw_token, access ]
  end

  def revoke!
    transaction do
      update!(revoked_at: Time.current)
      tokens.delete_all
    end
  end

  def revoked? = revoked_at.present?
  def pasted? = client.client_id == Oauth::Client::PASTED

  def record_use!
    update_column(:last_used_at, Time.current) if last_used_at.nil? || last_used_at < TOUCH_INTERVAL.ago
  end

  private

  def client_allows_scope
    errors.add(:scope, "isn't allowed for #{client.name}") unless client&.allows_scope?(scope)
  end
end
