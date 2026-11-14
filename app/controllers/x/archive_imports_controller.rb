class X::ArchiveImportsController < ApplicationController
  def create
    file = params[:file]
    raise X::ArchiveImport::Invalid, "Choose the archive .zip file." unless file.respond_to?(:tempfile)
    import = X::ArchiveImport.start!(file.tempfile.path)
    redirect_to x_sources_path(anchor: "archive"), notice: "Importing your archive of #{import.generated_at.to_date.to_fs(:long)}. A large one takes a few minutes; reload this page to see what was added."
  rescue X::ArchiveImport::Invalid => error
    redirect_to x_sources_path(anchor: "archive"), alert: error.message
  end
end
