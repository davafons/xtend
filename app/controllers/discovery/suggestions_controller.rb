class Discovery::SuggestionsController < ApplicationController
  def refresh
    X::SourcePost.transaction { X::SourcePost.reconcile_all! }
    redirect_to root_path, notice: "Saved conversation matches refreshed. No X API reads were made."
  end

  def create
    count = Discovery::Suggestion.capture_links!(params[:links])
    redirect_to settings_path(anchor: "discovery"), notice: "Saved #{count} source links. No API calls or verified relationship changes were made."
  rescue Discovery::Suggestion::Invalid => error
    redirect_to settings_path(anchor: "discovery"), alert: error.message
  end
end
