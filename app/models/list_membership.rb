class ListMembership < ApplicationRecord
  include WorkspaceScoped
  SOURCES = %w[owner ai].freeze
  belongs_to :list
  belongs_to :person
  validates :source, inclusion: { in: SOURCES }
  validates :person_id, uniqueness: { scope: :list_id }
end
