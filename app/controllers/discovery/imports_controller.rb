class Discovery::ImportsController < ApplicationController
  def create
    file = params[:file]
    raise Discovery::CandidateImport::Invalid, "Choose a discovery JSON file." unless file.respond_to?(:read)
    count = Discovery::CandidateImport.call(file.read(Discovery::CandidateImport::MAX_BYTES + 1))
    redirect_to settings_path, notice: "Imported #{count} candidate posts. This does not confirm replies or follow relationships."
  rescue Discovery::CandidateImport::Invalid => error
    redirect_to settings_path, alert: error.message
  end
end
