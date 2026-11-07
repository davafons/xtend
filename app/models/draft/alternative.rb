# Another version of a draft's idea, written by the owner or proposed by Grok. Using one swaps it with the
# main text, so nothing is lost.
class Draft::Alternative < ApplicationRecord
  include WorkspaceScoped
  self.table_name = "draft_alternatives"
  belongs_to :draft, touch: true

  validates :body, presence: true, length: { maximum: 25_000 }
  validates :source, inclusion: { in: Draft::SOURCES }
  validates :note, length: { maximum: 200 }

  delegate :parts, :part_lengths, :over_limit?, :thread?, to: :preview

  def preview
    Draft.new(body: body)
  end
end
