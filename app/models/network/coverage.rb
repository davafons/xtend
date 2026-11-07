# What the network data rests on, so the page can say how much was collected and when.
class Network::Coverage
  def interactions_by_kind
    @interactions_by_kind ||= X::Interaction.group(:kind).count
  end

  def follow_edges
    @follow_edges ||= X::FollowEdge.count
  end

  def accounts
    @accounts ||= X::Account.count
  end

  def posts
    @posts ||= X::SourcePost.count
  end

  def last_capture_at
    @last_capture_at ||= X::SyncRun.where(mode: "capture").maximum(:finished_at)
  end

  def empty?
    interactions_by_kind.empty? && follow_edges.zero?
  end
end
