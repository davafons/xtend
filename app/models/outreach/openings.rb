# Posts worth a reply now: fresh top-level posts from prospects you haven't answered, and discovery picks that
# match your interests. Each says why it is here. Replying happens on X; nothing here counts until a capture or
# sync confirms the reply.
class Outreach::Openings
  LIMIT = 30
  # A busy poster gets their newest few, so one person can't fill the list.
  PER_AUTHOR = 2
  DISCOVERY_RECENT = Outreach::Prospects::RECENT

  Opening = Data.define(:post, :author, :prospect, :discovery, :score) do
    delegate :x_id, :published_at, to: :post
    def url = "https://x.com/#{author&.handle || 'i'}/status/#{x_id}"
    def body = post.body
  end

  def initialize(prospects)
    @prospects = prospects
  end

  def to_a
    @openings ||= begin
      seen = {}
      @prospects.all.each do |prospect|
        prospect.recent_posts.first(PER_AUTHOR).each do |post|
          seen[post.x_id] = Opening.new(post, prospect.person || prospect.account, prospect, nil, prospect.score + freshness(post.published_at))
        end
      end
      discovery.each do |post|
        source = sources[post.x_id] || post
        current = seen[post.x_id]
        score = (current&.score || 0) + post.rank + freshness(post.published_at)
        seen[post.x_id] = Opening.new(current&.post || source, post.person, current&.prospect || @prospects.find(post.person.x_id), post, score)
      end
      seen.values.sort_by { |opening| [ -opening.score, -opening.published_at.to_f ] }.first(LIMIT)
    end
  end

  def size = to_a.size

  private

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
