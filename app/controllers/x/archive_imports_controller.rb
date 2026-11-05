class X::ArchiveImportsController < ApplicationController
  def create
    file = params[:file]
    raise X::ArchiveImport::Invalid, "Choose the archive .zip file." unless file.respond_to?(:tempfile)
    import = X::ArchiveImport.import!(file.tempfile.path)
    redirect_to settings_path(anchor: "archive"), notice: "Imported #{import.direct_messages_count} new one-to-one DMs (sender and time only). #{import.skipped_count} group or self messages skipped."
  rescue X::ArchiveImport::Invalid => error
    redirect_to settings_path(anchor: "archive"), alert: error.message
  end
end
