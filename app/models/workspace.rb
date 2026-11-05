class Workspace < ApplicationRecord
  has_many :users, dependent: :destroy
  validates :name, presence: true
  validates :monthly_budget_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100_000 }

  # The connector token identifies its workspace. Only its digest is stored, and the lookup compares digests.
  def self.find_by_mcp_token(token)
    return if token.blank?
    digest = mcp_digest(token)
    workspace = find_by(mcp_token_digest: digest)
    workspace if workspace && ActiveSupport::SecurityUtils.secure_compare(workspace.mcp_token_digest, digest)
  end

  def interests
    builder_interests.lines.map(&:strip).reject(&:blank?)
  end

  # The MCP connector token is shown once; only its digest is stored.
  def issue_mcp_token!
    token = "crm_#{SecureRandom.urlsafe_base64(32)}"
    update!(mcp_token_digest: self.class.mcp_digest(token), mcp_token_created_at: Time.current, mcp_token_used_at: nil)
    token
  end

  def revoke_mcp_token!
    update!(mcp_token_digest: nil, mcp_token_created_at: nil, mcp_token_used_at: nil)
  end

  def self.mcp_digest(token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, token.to_s)
  end

  def grok_context
    graph = Follow::Graph.latest
    {
      format: "twitter-crm-context-v1", exported_at: Time.current.iso8601,
      demo: Rails.configuration.x.demo, interests: interests,
      coverage: "Only imported or directly recorded evidence; not a complete X history.",
      people: Person.order(:name).includes(:pin, :follow_protection, :reply_events).map { |person|
        { id: person.id, handle: person.handle, name: person.name,
          description: person.description, reply_state: person.reply_state,
          outgoing_replies: person.outgoing_count, incoming_replies: person.incoming_count,
          follow_state: person.follow_state(graph), pinned: person.pin.present?,
          keep_following: person.follow_protection.present? }
      }
    }
  end
end
