class Current < ActiveSupport::CurrentAttributes
  class MissingWorkspace < StandardError; end
  attribute :session, :workspace
  delegate :user, to: :session, allow_nil: true

  def session=(value)
    super
    self.workspace = value&.user&.workspace
  end

  # Scoped queries call this, so a request, task, or test without a workspace fails instead of reading everyone's data.
  def workspace!
    workspace || raise(MissingWorkspace, "No workspace is set. Sign in, or wrap the code in Current.set(workspace: ...).")
  end
end
