# Posts worth a reply now: fresh top-level posts from prospects you haven't answered, and discovery picks that
# match your interests. Each says why it is here. Replying happens on X; nothing here counts until a capture or
# sync confirms the reply.
class Outreach::Openings
  LIMIT = 30
  # A busy poster gets their newest few, so one person can't fill the list.
  PER_AUTHOR = 2
  DISCOVERY_RECENT = Outreach::Prospects::RECENT

  Opening = Data.define(:post, :author, :prospect, :discovery, :score, :payoff) do
    delegate :x_id, :published_at, to: :post
    def url = "https://x.com/#{author&.handle || 'i'}/status/#{x_id}"
    def body = post.body
  end

  def initialize(prospects, payoff: Outreach::Payoff.new)
    @prospects = prospects
    @payoff = payoff
  end

  # Today's share of the list: as many posts as the session still needs, split as the growth plan says between
  # your circle (the Circle and Inner circle lists) and reach (everyone else). When one side runs short, the
  # other fills its places. Each side keeps the ranking's order.
  Today = Data.define(:circle, :reach, :remaining) do
    def size = circle.size + reach.size
    def empty? = size.zero?
  end

  def today(remaining)
    circle, reach = ranked.partition { |opening| circle_ids.include?(opening.author&.x_id) }
    circle_places = (remaining * Outreach::Growth::CIRCLE_SHARE).round
    reach_places = remaining - circle_places
    reach_places += [ circle_places - circle.size, 0 ].max
    circle_places += [ reach_places - reach.size, 0 ].max
    Today.new(circle.first(circle_places), reach.first(reach_places), remaining)
  end

  def to_a
    @openings ||= ranked.first(LIMIT)
  end

  def size = to_a.size

  # Every opening, best first.
  def ranked
    @ranked ||= begin
      seen = {}
      @prospects.all.each do |prospect|
        prospect.recent_posts.first(PER_AUTHOR).each do |post|
          seen[post.x_id] = Opening.new(post, prospect.person || prospect.account, prospect, nil, prospect.score + freshness(post.published_at), nil)
        end
      end
      discovery.each do |post|
        source = sources[post.x_id] || post
        current = seen[post.x_id]
        score = (current&.score || 0) + post.rank + freshness(post.published_at)
        seen[post.x_id] = Opening.new(current&.post || source, post.person, current&.prospect || @prospects.find(post.person.x_id), post, score, nil)
      end
      # What your past replies brought lifts openings like the ones that paid off.
      seen.transform_values! do |opening|
        points, reason = @payoff.lift(opening.author)
        points ? opening.with(score: opening.score + points, payoff: reason) : opening
      end
      seen.values.sort_by { |opening| [ -opening.score, -opening.published_at.to_f ] }
    end
  end

  private

  def circle_ids
    @circle_ids ||= List.circle_people.where.not(x_id: nil).pluck(:x_id).to_set
  end

  # Up to 12 points for a post in its first hours, falling to none at two days old.
  def freshness(at)
    hours = (Time.current - at) / 1.hour
    [ (12 - hours / 4).round, 0 ].max
  end

  def discovery
    @discovery ||= Outreach::Candidate.opportunities.where(published_at: DISCOVERY_RECENT.ago..).limit(LIMIT).to_a
      .reject { |post| Outreach::Prospects::AUTOMATED.include?(post.person.handle) }
  end

  # Captured copies carry counts and media that the discovery record does not.
  def sources
    @sources ||= X::SourcePost.where(x_id: discovery.map(&:x_id)).index_by(&:x_id)
  end
end
