# What your past replies brought, from X analytics on each reply (X::PostAnalytic): profile visits and follows, by
# the size of the account you answered and by person. Outreach uses it to lift openings like the ones that paid
# off. It only lifts, never buries. A band needs MINIMUM counted replies, and replies that paid off to at least
# PAYING_PEOPLE different people, before it says anything, so a thin history or one lucky reply stays quiet.
class Outreach::Payoff
  BANDS = [ [ 0, 1_000, "under 1K" ], [ 1_000, 5_000, "1K–5K" ], [ 5_000, 20_000, "5K–20K" ], [ 20_000, 100_000, "20K–100K" ], [ 100_000, nil, "over 100K" ] ].freeze
  MINIMUM = 3
  PAYING_PEOPLE = 2
  # A follow counts as much as this many profile visits.
  FOLLOW_WEIGHT = 5
  MAX_POINTS = 15

  Result = Data.define(:label, :replies, :visits, :follows, :paying_people) do
    def value = visits + follows * FOLLOW_WEIGHT
    def per_reply = value.fdiv(replies)
    def summary = "#{visits} profile #{'visit'.pluralize(visits)}#{", #{follows} #{'follow'.pluralize(follows)}" if follows.positive?} from #{replies} #{'reply'.pluralize(replies)}"
  end

  # { label => Result } for bands with enough counted replies.
  def bands
    @bands ||= replies.group_by { |reply| band_for(reply[:followers]) }.except(nil).filter_map do |label, rows|
      next if rows.size < MINIMUM
      [ label, result(label, rows) ]
    end.to_h
  end

  def overall
    @overall ||= result("all", replies) if replies.any?
  end

  # Your counted replies to one person: Result or nil.
  def for_person(person_id)
    rows = replies.select { |reply| reply[:person_id] == person_id }
    result("them", rows) if rows.any?
  end

  # [points, reason text] for answering this author, or nil when nothing in your history says they pay off more.
  def lift(author)
    person = for_person(author.id) if author.is_a?(Person)
    return [ MAX_POINTS, "Your replies to them brought #{person.summary.sub(/ from .*/, '')}" ] if person && person.value.positive?
    band = bands[band_for(author.followers_count)]
    return unless band && band.paying_people >= PAYING_PEOPLE && overall && overall.per_reply.positive? && band.per_reply > overall.per_reply
    points = (MAX_POINTS * (band.per_reply / overall.per_reply - 1)).round.clamp(1, MAX_POINTS)
    [ points, "Accounts with #{band.label} followers: #{band.summary}" ]
  end

  def band_for(followers)
    return if followers.nil?
    BANDS.find { |low, high, _| followers >= low && (high.nil? || followers < high) }&.last
  end

  private

  def result(label, rows)
    paying = rows.select { |row| row[:visits].positive? || row[:follows].positive? }.map { _1[:person_id] }.uniq.size
    Result.new(label, rows.size, rows.sum { _1[:visits] }, rows.sum { _1[:follows] }, paying)
  end

  def replies
    @replies ||= begin
      events = ReplyEvent.where(direction: "outgoing").includes(:person).to_a
      analytics = X::PostAnalytic.where(post_x_id: events.map(&:x_id)).index_by(&:post_x_id)
      events.filter_map do |event|
        found = analytics[event.x_id] or next
        { person_id: event.person_id, followers: event.person.followers_count,
          visits: found.metric("ProfileVisits").to_i, follows: found.metric("Follows").to_i }
      end
    end
  end
end
