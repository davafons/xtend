# Imports an uploaded X archive outside the web request. Nothing here calls X.
class X::ArchiveImportJob < ApplicationJob
  queue_as :archive_imports
  limits_concurrency to: 1, key: ->(workspace, *) { workspace }, duration: 1.hour

  def perform(workspace, import_id)
    Current.set(workspace: workspace) do
      X::ArchiveImport.find_by(id: import_id)&.run!
    end
  end
end
