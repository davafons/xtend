# Conversation activity and follower totals over time, side by side. Charts read saved data only. Dragging
# across a chart narrows everything on the page to a from/to date range.
class InsightsController < ApplicationController
  def show
    @activity = Network::Activity.new(period: params[:period], range: date_range_param)
    @followers = Follow::Snapshot.follower_counts(since: @activity.starts_at, before: @activity.ends_at)
    @changes = Follow::Snapshot.follower_changes(since: @activity.starts_at, before: @activity.ends_at)
    replies = ReplyEvent.where(occurred_at: @activity.starts_at..@activity.ends_at)
    coverage = X::MentionCoverage.new
    @answers = Network::AnswerRate.new(replies, coverage: coverage)
    @outreach_answers = Network::AnswerRate.new(replies.where(classification: "initial"), coverage: coverage)
    @follow_backs = Follow::FollowBacks.new(replies)
    @posts = Network::PostPerformance.new(since: @activity.starts_at, before: @activity.ends_at)
    @x_analytics = Network::XAnalytics.new(@activity)
  end
end
