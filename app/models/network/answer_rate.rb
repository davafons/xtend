# How often your replies get a direct reply back from the same person within a week (the PRD's reply answer
# rate). Each reply counts once. A reply only joins the rate once its week is over and the mentions reads
# cover that whole week; answers seen outside that coverage are reported separately, never mixed in.
class Network::AnswerRate
  WINDOW = 7.days
  MINIMUM = 5

  def initialize(replies, coverage: X::MentionCoverage.new, now: Time.current)
    @replies = replies.where(direction: "outgoing").to_a
    @coverage = coverage
    @now = now
  end

  def total = @replies.size
  def open = @replies.count { |reply| reply.occurred_at + WINDOW > @now }
  def eligible = closed.select { |reply| covered?(reply) }
  def uncovered = closed.reject { |reply| covered?(reply) }
  def answered = eligible.count { |reply| answered?(reply) }
  def answered_outside_coverage = uncovered.count { |reply| answered?(reply) }

  def available?
    eligible.size >= MINIMUM
  end

  # A fraction from 0 to 1, or nil while too few replies have a covered, finished week.
  def rate
    answered.fdiv(eligible.size) if available?
  end

  def answered?(reply)
    answers.fetch(reply.x_id, []).any? { |person_id, at| person_id == reply.person_id && at > reply.occurred_at && at <= reply.occurred_at + WINDOW }
  end

  def covered_until = @coverage.covered_until

  private

  def closed
    @closed ||= @replies.select { |reply| reply.occurred_at + WINDOW <= @now }
  end

  def covered?(reply)
    @coverage.covers?(reply.occurred_at, reply.occurred_at + WINDOW)
  end

  def answers
    @answers ||= ReplyEvent.where(direction: "incoming", target_x_id: @replies.map(&:x_id))
      .pluck(:target_x_id, :person_id, :occurred_at).group_by(&:first).transform_values { |rows| rows.map { |_, person_id, at| [ person_id, at ] } }
  end
end
