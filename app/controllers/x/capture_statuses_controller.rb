# When the browser extension last delivered something new, so open pages can refresh themselves.
class X::CaptureStatusesController < ApplicationController
  def show
    workspace = Current.workspace
    render json: { captured_at: workspace.captured_at&.iso8601(3), summary: helpers.capture_summary(workspace.last_capture) }
  end
end
