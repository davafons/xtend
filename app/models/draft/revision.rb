# A saved state of a draft's main text. Quick successive saves by the same author update one revision
# instead of piling up, so the history shows meaningful steps.
class Draft::Revision < ApplicationRecord
  include WorkspaceScoped
  self.table_name = "draft_revisions"
  COALESCE_WITHIN = 10.minutes
  belongs_to :draft

  validates :source, inclusion: { in: Draft::SOURCES }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
end
