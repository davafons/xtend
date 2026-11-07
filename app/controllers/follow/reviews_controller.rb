class Follow::ReviewsController < ApplicationController
  BATCH_SIZES = [ 5, 10, 25, 50 ].freeze
  FILTERS = %i[reason inactive quiet mutuals sort batch].freeze

  def index
    @cleanup = Follow::Cleanup.new(reason: params[:reason], inactive_days: params[:inactive], quiet_days: params[:quiet],
      mutuals: params[:mutuals], sort: params[:sort])
    @batch = BATCH_SIZES.include?(params[:batch].to_i) ? params[:batch].to_i : BATCH_SIZES.first
    if @cleanup.ready?
      @counts = @cleanup.counts
      @candidates = @cleanup.candidates(@batch)
    else
      @counts = {}
      @candidates = []
    end
    @coverage = Person::Interactions.coverage
    @reviews = Follow::Review.where(reviewed_on: Date.current).includes(:person).order(updated_at: :desc)
    @tally = @reviews.group_by(&:decision).transform_values(&:size)
  end

  def create
    person = Person.find(params[:person_id])
    decision = params[:decision]
    unless %w[keep defer reported_unfollow].include?(decision)
      return head :unprocessable_entity
    end
    Follow::Review.record!(person, decision)
    notice = { "keep" => "Keeping #{person.name}.", "defer" => "Deferred #{person.name} until tomorrow.",
      "reported_unfollow" => "Unfollow of #{person.name} reported. With the browser capture on, unfollowing on X records itself." }.fetch(decision)
    redirect_to follow_reviews_path(review_filters), notice: notice
  end

  private

  def review_filters
    params.permit(*FILTERS).to_h.compact_blank
  end
  helper_method :review_filters
end
