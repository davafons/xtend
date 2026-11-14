# A growth-plan checklist item the owner ticked for a plan week, such as "one story post".
class Outreach::GrowthCheck < ApplicationRecord
  include WorkspaceScoped
  self.table_name = "outreach_growth_checks"

  KEYS = Outreach::Growth::SETUP.merge(Outreach::Growth::WEEKLY).select { |_, (_, _, kind)| kind == :manual }.keys.freeze

  validates :key, inclusion: { in: KEYS }, uniqueness: { scope: [ :workspace_id, :week ] }
  validates :week, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: Outreach::Growth::WEEKS }
end
