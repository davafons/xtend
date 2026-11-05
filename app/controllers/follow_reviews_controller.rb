class FollowReviewsController < ApplicationController
  BATCH_SIZES = [ 5, 10, 25 ].freeze
  QUIET_PERIODS = [ 30, 60, 90, 180 ].freeze
  SORTS = {
    "quietest" => [ "Longest quiet", nil ],
    "largest" => [ "Most followers", "people.followers_count IS NULL, people.followers_count DESC" ],
    "smallest" => [ "Fewest followers", "people.followers_count IS NULL, people.followers_count ASC" ],
    "quiet" => [ "Least active", "people.posts_count IS NULL, people.posts_count ASC" ],
    "name" => [ "Name", "people.name COLLATE NOCASE ASC" ]
  }.freeze

  def index
    @graph = FollowGraph.latest
    @followers = @graph.followers
    @following = FollowSnapshot.latest_complete("following")
    @batch = BATCH_SIZES.include?(params[:batch].to_i) ? params[:batch].to_i : BATCH_SIZES.first
    @quiet = QUIET_PERIODS.include?(params[:quiet].to_i) ? params[:quiet].to_i : Person::CLEANUP_QUIET_PERIOD.in_days.to_i
    candidates = Person.cleanup_candidates(quiet_for: @quiet.days)
    @remaining = candidates.count
    @sort = SORTS.key?(params[:sort]) ? params[:sort] : "quietest"
    if @sort == "quietest"
      # Nothing observed first, then the oldest last interaction.
      index = Person::Interactions.index(candidates)
      ids = index.sort_by { |id, interactions| [interactions.latest ? 1 : 0, interactions.latest&.at.to_f, id] }.first(@batch).map(&:first)
      @candidates = Person.where(id: ids).includes(:pin).index_by(&:id).values_at(*ids)
    else
      @candidates = candidates.reorder(Arel.sql(SORTS.fetch(@sort).last), :id).includes(:pin).limit(@batch).to_a
    end
    @interactions = Person::Interactions.index(@candidates)
    @coverage = Person::Interactions.coverage
    @latest_posts = XSourcePost.where(author_x_id: @candidates.map(&:x_id).compact, repost: false)
      .group(:author_x_id).maximum(:published_at)
    @reviews = FollowReview.where(reviewed_on: Date.current).includes(:person).order(updated_at: :desc)
    @tally = @reviews.group_by(&:decision).transform_values(&:size)
  end

  def create
    person = Person.find(params[:person_id])
    decision = params[:decision]
    unless %w[keep defer reported_unfollow].include?(decision)
      return head :unprocessable_entity
    end
    FollowReview.record!(person, decision)
    notice = { "keep" => "Keeping #{person.name}.", "defer" => "Deferred #{person.name} until tomorrow.",
      "reported_unfollow" => "Unfollow of #{person.name} reported. X status is unchanged until a later following check verifies it." }.fetch(decision)
    redirect_to follow_reviews_path(batch: params[:batch].presence, sort: params[:sort].presence, quiet: params[:quiet].presence), notice: notice
  end
end
