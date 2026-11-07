# What has been collected from X, its coverage, and the manual collection actions.
class X::SourcesController < ApplicationController
  def show
    @cycle = X::BillingCycle.current
    @runs = X::SyncRun.where.not(mode: "capture").order(created_at: :desc).limit(12)
    captures = X::SyncRun.where(mode: "capture", created_at: 7.days.ago..).select(:id)
    @capture_totals = { posts: X::SourcePost.where(x_sync_run_id: captures).count,
      likes: Engagement.where(kind: "like", x_sync_run_id: captures).count,
      bookmarks: Engagement.where(kind: "bookmark", x_sync_run_id: captures).count }
    @followers = Follow::Snapshot.latest("followers")
    @following = Follow::Snapshot.latest("following")
  end
end
