class DiscoverySuggestionsController < ApplicationController
  def refresh
    XSourcePost.transaction { XSourcePost.reconcile_all! }
    redirect_to root_path, notice: "Saved conversation matches refreshed. No X API reads were made."
  end

  def create
    count = DiscoverySuggestion.capture_links!(params[:links])
    redirect_to settings_path(anchor: "discovery"), notice: "Saved #{count} source links. No API calls or verified relationship changes were made."
  rescue DiscoverySuggestion::Invalid => error
    redirect_to settings_path(anchor: "discovery"), alert: error.message
  end
end
