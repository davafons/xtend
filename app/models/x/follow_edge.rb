# One account following another, as seen on a follow list. Lists are only what was scrolled, so a missing edge
# never means someone doesn't follow. The owner's own lists stay authoritative in Follow::Snapshot.
# `followed_at` is when X said the follow happened, from a "followed you" notification; the newest one wins, since
# a follow after an unfollow starts again.
class X::FollowEdge < ApplicationRecord
  include WorkspaceScoped
  self.table_name = "x_follows"

  def self.record!(follower:, followed:, seen_on:, at: Time.current, followed_at: nil)
    return if follower.blank? || followed.blank? || follower == followed
    edge = find_or_initialize_by(follower_x_id: follower, followed_x_id: followed)
    edge.followed_at = [ edge.followed_at, followed_at ].compact.max
    edge.first_seen_at = [ edge.first_seen_at || at, followed_at ].compact.min
    edge.update!(last_seen_at: at, seen_on: seen_on)
  end
end
