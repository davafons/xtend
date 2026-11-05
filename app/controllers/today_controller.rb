class TodayController < ApplicationController
  def index
    @daily_session = DailySession.current
    @posts = Post.opportunities.limit(10)
    @available = Post.opportunities.count
    @pending = ReplyReport.count
    @pinned_people = Person.pinned.alphabetical.limit(4)
    @review_count = Person.cleanup_candidates.count
    @graph = FollowGraph.latest
    @reports = ReplyReport.includes(post: :person).order(created_at: :desc)
    @set_aside = PostDisposition.where(updated_at: Date.current.all_day).includes(post: :person).order(updated_at: :desc).limit(20)
    @last_reply_check = XSyncRun.where(dataset: "own_posts").order(created_at: :desc).first
  end
end
