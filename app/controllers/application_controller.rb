class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  # The from and to params, ISO dates, as a date range; nil when either is missing or invalid.
  def date_range_param
    from, to = params.values_at(:from, :to).map { |date| Date.iso8601(date.to_s) rescue nil }
    from..to if from && to && from <= to
  end
end
