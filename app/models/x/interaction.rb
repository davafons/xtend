# A directed interaction between two accounts, derived from captured posts and engagement lists.
class X::Interaction < ApplicationRecord
  include WorkspaceScoped
  self.table_name = "x_interactions"
  KINDS = %w[reply quote repost mention like].freeze

  validates :kind, inclusion: { in: KINDS }

  def self.record!(kind:, source:, target:, post:, target_post: nil, occurred_at: nil, at: Time.current)
    return if source.blank? || target.blank? || source == target
    interaction = find_or_initialize_by(kind: kind, post_x_id: post, source_x_id: source, target_x_id: target)
    interaction.assign_attributes(target_post_x_id: target_post, occurred_at: occurred_at || interaction.occurred_at, observed_at: at)
    interaction.save!
    interaction.previously_new_record?
  end
end
