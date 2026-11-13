class PersonTag < ApplicationRecord
  include WorkspaceScoped
  SOURCES = %w[owner ai].freeze
  belongs_to :person
  belongs_to :tag
  validates :source, inclusion: { in: SOURCES }
  validates :tag_id, uniqueness: { scope: :person_id }

  # Unused tags disappear, so the vocabulary offered to the owner and to AI stays current.
  after_destroy_commit { tag.destroy if tag.person_tags.none? }
end
