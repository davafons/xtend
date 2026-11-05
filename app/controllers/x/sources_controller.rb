# What has been collected from X, its coverage, and the manual collection actions.
class X::SourcesController < ApplicationController
  def show
    @cycle = X::BillingCycle.current
    @runs = X::SyncRun.order(created_at: :desc).limit(12)
    @followers = Follow::Snapshot.latest("followers")
    @following = Follow::Snapshot.latest("following")
  end
end
