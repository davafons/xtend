# Owner data belongs to one workspace. The default scope makes every query, including associations
# and subqueries, filter by Current.workspace, and raises when no workspace is set.
module WorkspaceScoped
  extend ActiveSupport::Concern

  included do
    belongs_to :workspace, default: -> { Current.workspace! }
    default_scope { where(workspace_id: Current.workspace!.id) }
  end
end
