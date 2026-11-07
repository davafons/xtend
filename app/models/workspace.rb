class Workspace < ApplicationRecord
  has_many :users, dependent: :destroy
  validates :name, presence: true
  validates :monthly_budget_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100_000 }

  # Bearer tokens identify their workspace: :mcp for the Grok connector, :capture for the browser extension.
  # Only a digest is stored, and the lookup compares digests.
  def self.find_by_token(kind, token)
    return if token.blank?
    digest = token_digest(token)
    workspace = find_by("#{kind}_token_digest": digest)
    workspace if workspace && ActiveSupport::SecurityUtils.secure_compare(workspace["#{kind}_token_digest"], digest)
  end

  def self.find_by_mcp_token(token) = find_by_token(:mcp, token)

  def interests
    builder_interests.lines.map(&:strip).reject(&:blank?)
  end

  # A token is shown once; issuing another replaces it.
  def issue_token!(kind)
    token = "#{kind == :mcp ? "crm" : "crm_#{kind}"}_#{SecureRandom.urlsafe_base64(32)}"
    update!("#{kind}_token_digest": self.class.token_digest(token), "#{kind}_token_created_at": Time.current, "#{kind}_token_used_at": nil)
    token
  end

  def revoke_token!(kind)
    update!("#{kind}_token_digest": nil, "#{kind}_token_created_at": nil, "#{kind}_token_used_at": nil)
  end

  def touch_token_use!(kind)
    used_at = self["#{kind}_token_used_at"]
    update_column("#{kind}_token_used_at", Time.current) if used_at.nil? || used_at < 1.minute.ago
  end

  def issue_mcp_token! = issue_token!(:mcp)
  def revoke_mcp_token! = revoke_token!(:mcp)

  def self.token_digest(token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, token.to_s)
  end

  def grok_context
    graph = Follow::Graph.latest
    {
      format: "twitter-crm-context-v1", exported_at: Time.current.iso8601,
      demo: Rails.configuration.x.demo, interests: interests,
      coverage: "Only imported or directly recorded evidence; not a complete X history.",
      people: Person.order(:name).includes(:pin, :follow_protection, :reply_events, :tags).map { |person|
        { id: person.id, handle: person.handle, name: person.name,
          description: person.description, reply_state: person.reply_state,
          outgoing_replies: person.outgoing_count, incoming_replies: person.incoming_count,
          follow_state: person.follow_state(graph), tags: person.tags.map(&:name), pinned: person.pin.present?,
          keep_following: person.follow_protection.present? }
      }
    }
  end
end
