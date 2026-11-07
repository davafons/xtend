class Follow::HistoryController < ApplicationController
  VIEWS = { "current" => "Current followers", "not_followed_back" => "You don't follow back", "new" => "New", "lost" => "Lost" }.freeze

  def index
    @graph = Follow::Graph.latest
    @snapshot = @graph.followers
    @checks = Follow::Snapshot.where(direction: "followers").where.not(completed_at: nil).order(observed_at: :desc).limit(2).to_a
    @view = VIEWS.key?(params[:view]) ? params[:view] : "current"
    following = @graph.following_ids_query
    ongoing = Follow::FollowerPeriod.ongoing
    @counts = {
      "current" => ongoing.count,
      "not_followed_back" => ongoing.where.not(person_id: following).count,
      "new" => Follow::FollowerPeriod.known_starts.count,
      "lost" => lost_scope.count
    }
    @new_since_last = @checks.size == 2 ? ongoing.where(first_snapshot_id: @checks.first.id).where.not(followed_after: nil).count : nil
    @lost_since_last = @checks.size == 2 ? Follow::FollowerPeriod.where(ended_snapshot_id: @checks.first.id).count : nil
    @follow_back = ongoing.where(person_id: following).count
    @duration = Follow::FollowerPeriod.completed_duration_summary
    @periods = case @view
    when "current" then ongoing.joins(:person).order(Arel.sql("follower_periods.followed_after IS NULL, follower_periods.first_seen_at DESC, people.followers_count DESC"))
    when "not_followed_back" then ongoing.where.not(person_id: following).joins(:person).order(Arel.sql("people.followers_count IS NULL, people.followers_count DESC"))
    when "new" then Follow::FollowerPeriod.known_starts.order(first_seen_at: :desc)
    when "lost" then lost_scope.order(ended_by: :desc)
    end.includes(person: [ :reply_events, :follow_protection, :pin ]).limit(300)
    @refollowed = ongoing.where(person_id: @periods.map(&:person_id)).where.not(id: @periods.map(&:id)).pluck(:person_id).to_set
  end

  private

  def lost_scope
    Follow::FollowerPeriod.ended.where.not(person_id: Follow::FollowerPeriod.ongoing.select(:person_id))
  end
end
