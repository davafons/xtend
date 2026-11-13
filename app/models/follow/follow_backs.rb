# Who started following you after you first replied to them. It only judges people whose first outreach reply
# sits between two complete follower checks: the check before shows they weren't following, and a later one
# shows whether they are now. Anyone else is left out, because partial or missing checks prove nothing.
class Follow::FollowBacks
  def initialize(replies)
    @firsts = replies.where(direction: "outgoing", classification: "initial").group(:person_id).minimum(:occurred_at)
  end

  # People whose first outreach reply both checks bracket and who weren't following before it.
  def judged
    @judged ||= @firsts.filter_map do |person_id, at|
      before = checks.reverse.find { |check| check.observed_at <= at }
      next unless before && checks.any? { |check| check.observed_at > at }
      person_id unless members.fetch(before.id).include?(person_id)
    end
  end

  def followed
    @followed ||= judged.select { |person_id| members.any? { |check_id, ids| observed_at.fetch(check_id) > @firsts.fetch(person_id) && ids.include?(person_id) } }
  end

  def available?
    judged.any?
  end

  private

  def checks
    @checks ||= Follow::Snapshot.where(direction: "followers").where.not(completed_at: nil).order(:observed_at).to_a
  end

  def observed_at
    @observed_at ||= checks.to_h { |check| [ check.id, check.observed_at ] }
  end

  def members
    @members ||= Follow::Membership.where(follow_snapshot_id: checks.map(&:id)).pluck(:follow_snapshot_id, :person_id)
      .group_by(&:first).transform_values { |rows| rows.map(&:last).to_set }.then { |found| checks.to_h { |check| [ check.id, found.fetch(check.id, Set.new) ] } }
  end
end
