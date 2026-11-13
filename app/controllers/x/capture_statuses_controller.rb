# How the browser extension is doing. Open pages poll the JSON to refresh themselves when a batch changed
# something; the page shows whether the extension is reaching Xtend and what it delivered lately.
class X::CaptureStatusesController < ApplicationController
  def show
    workspace = Current.workspace
    respond_to do |format|
      format.html { @activity = X::CaptureActivity.new(workspace) }
      format.json { render json: { captured_at: workspace.captured_at&.iso8601(3), summary: helpers.capture_summary(workspace.last_capture) } }
    end
  end
end
