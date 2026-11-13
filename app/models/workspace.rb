class Workspace < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :oauth_grants, class_name: "Oauth::Grant", dependent: :destroy
  has_many :oauth_authorization_codes, class_name: "Oauth::AuthorizationCode", dependent: :delete_all
  validates :name, presence: true
  validates :monthly_budget_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100_000 }

  def interests
    builder_interests.lines.map(&:strip).reject(&:blank?)
  end

  def ai_context
    graph = Follow::Graph.latest
    {
      format: "xtend-context-v1", exported_at: Time.current.iso8601,
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
