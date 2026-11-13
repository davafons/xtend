# People worth engaging more, ranked from saved data. Each prospect carries short reasons:
#
# - reach_back: they reached you (replies, mentions, quotes, likes) on more posts than you reached them;
# - quiet: you have reached each other, but nothing was seen either way for QUIET_AFTER (DMs count as contact);
# - posting: a mutual or pinned person has top-level posts from the last RECENT you haven't replied to;
# - network: at least NETWORK_MIN people you follow or talk with reached them lately, and nothing between you was seen.
#
# Counts are distinct posts in collected data, so "none seen" never means "never happened".
class Outreach::Prospects
  QUIET_AFTER = 14.days
  RECENT = 48.hours
  COOLDOWN = 2.days
  NETWORK_WINDOW = 90.days
  NETWORK_MIN = 2
  BIG_ACCOUNT = 100_000
  AUTOMATED = %w[grok bot].freeze
  LIMIT = 60
  # Outreach is English-only; X marks posts without words (links, emoji, media) with these codes.
  ENGLISH = %w[en und zxx qme qam qct].freeze

  REASONS = {
    "reach_back" => { label: "Reaching out", icon: "arrow-down-left", meaning: :them },
    "quiet" => { label: "Gone quiet", icon: "moon", meaning: :both },
    "posting" => { label: "Posting", icon: "chat-bubble-oval-left", meaning: :neutral },
    "network" => { label: "In your network", icon: "share", meaning: :neutral }
  }.freeze

  Reason = Data.define(:key, :detail, :note) do
    def label = REASONS.fetch(key)[:label]
    def icon = REASONS.fetch(key)[:icon]
    def meaning = REASONS.fetch(key)[:meaning]
  end

  Prospect = Data.define(:x_id, :person, :account, :reasons, :score, :last_touch_at, :recent_posts) do
    def name = person&.name || account.name
    def handle = person&.handle || account.handle
    def profile_url = "https://x.com/#{handle}"
    def reason?(key) = reasons.any? { |reason| reason.key == key }
  end

  attr_reader :reason, :graph

  def initialize(reason: nil, graph: Follow::Graph.latest)
    @reason = REASONS.key?(reason) ? reason : nil
    @graph = graph
    @owner = Current.workspace.owner_x_id.to_s
  end

  def all
    @all ||= @owner.blank? ? [] : rank
  end

  def to_a
    reason ? all.select { |prospect| prospect.reason?(reason) } : all
  end

  def counts
    REASONS.keys.index_with { |key| all.count { |prospect| prospect.reason?(key) } }
  end

  def find(x_id)
    @by_x_id ||= all.index_by(&:x_id)
    @by_x_id[x_id]
  end

  # Top-level English posts you have not replied to or set aside, newest first, by author.
  def recent_posts
    @recent_posts ||= begin
      authors = exchanges.keys | watched.keys | network.keys
      posts = X::SourcePost.where(author_x_id: authors, repost: false, reply_to_x_id: nil, published_at: RECENT.ago..Time.current)
        .where("language IS NULL OR language IN (?)", ENGLISH)
        .where.not(x_id: answered_ids).order(published_at: :desc)
      posts.group_by(&:author_x_id)
    end
  end

  private

  def rank
    people = Person.includes(:pin, :tags).where(x_id: candidates.keys).index_by(&:x_id)
    accounts = X::Account.where(x_id: candidates.keys - people.keys).index_by(&:x_id)
    candidates.filter_map do |x_id, reasons|
      person = people[x_id]
      account = accounts[x_id]
      next unless person || account
      next if AUTOMATED.include?((person || account).handle)
      exchange = exchanges[x_id]
      score = reasons.sum { |reason| weight(reason.key, x_id, exchange) }
      score += 10 if person&.pin
      score += 5 if person && mutual?(person)
      Prospect.new(x_id, person, account, reasons, score, exchange&.last_touch_at, recent_posts.fetch(x_id, []))
    end.sort_by { |prospect| [ -prospect.score, -(prospect.recent_posts.first&.published_at.to_f), prospect.name.downcase ] }.first(LIMIT)
  end

  def weight(key, x_id, exchange)
    case key
    when "reach_back" then 30 + 4 * [ exchange.incoming - exchange.outgoing, 10 ].min
    when "quiet" then 20 + 2 * [ exchange.incoming + exchange.outgoing, 10 ].min
    when "posting" then 15 + 5 * [ recent_posts.fetch(x_id).size, 4 ].min
    when "network" then 8 + 3 * [ network.fetch(x_id), 8 ].min
    end
  end

  # { x_id => [Reason] }
  def candidates
    @candidates ||= begin
      reasons = Hash.new { |hash, key| hash[key] = [] }
      exchanges.each do |x_id, exchange|
        next if x_id == @owner
        if exchange.reaching_back? && !exchange.reached_since?(COOLDOWN.ago)
          seen_from_you = exchange.outgoing.zero? ? "none seen from you" : "#{exchange.outgoing} from you"
          reasons[x_id] << Reason.new("reach_back", "#{exchange.incoming} from them · #{seen_from_you}",
            "They reached you on #{exchange.incoming} #{'post'.pluralize(exchange.incoming)}; #{seen_from_you} in collected data")
        end
        if exchange.two_way? && exchange.last_touch_at < QUIET_AFTER.ago
          days = ((Time.current - exchange.last_touch_at) / 1.day).floor
          reasons[x_id] << Reason.new("quiet", "Two-way · quiet #{days}d", "You have reached each other; nothing seen either way for #{days} days")
        end
      end
      watched.each do |x_id, why|
        posts = recent_posts.fetch(x_id, [])
        next if posts.empty?
        reasons[x_id] << Reason.new("posting", "#{why} · #{posts.size} new #{'post'.pluralize(posts.size)}",
          "#{why} with #{posts.size} unanswered #{'post'.pluralize(posts.size)} in the last #{RECENT.inspect}")
      end
      network.each do |x_id, sources|
        reasons[x_id] << Reason.new("network", "#{sources} of your people talk to them",
          "#{sources} people you follow or talk with reached them in #{NETWORK_WINDOW.inspect}; nothing seen between you")
      end
      reasons
    end
  end

  Exchange = Struct.new(:incoming_posts, :outgoing_posts, :incoming_at, :outgoing_at, :dm_at) do
    def incoming = incoming_posts.size
    def outgoing = outgoing_posts.size
    def reaching_back? = incoming.positive? && incoming > outgoing
    def two_way? = incoming.positive? && outgoing.positive?
    def reached_since?(time) = outgoing_at.present? && outgoing_at >= time
    def last_touch_at = [ incoming_at, outgoing_at, dm_at ].compact.max
  end

  # Everything seen between you and each account: public interactions in both directions, confirmed replies,
  # and DM metadata (which only moves the last contact, never the counts).
  def exchanges
    @exchanges ||= begin
      rows = Hash.new { |hash, key| hash[key] = Exchange.new(Set.new, Set.new, nil, nil, nil) }
      at = Arel.sql("COALESCE(occurred_at, observed_at)")
      X::Interaction.where(target_x_id: @owner).where.not(source_x_id: @owner).pluck(:source_x_id, :post_x_id, at).each do |x_id, post, time|
        touch(rows[x_id], :incoming, post, parse_time(time))
      end
      X::Interaction.where(source_x_id: @owner).where.not(target_x_id: @owner).pluck(:target_x_id, :post_x_id, at).each do |x_id, post, time|
        touch(rows[x_id], :outgoing, post, parse_time(time))
      end
      ReplyEvent.joins(:person).where.not(people: { x_id: nil }).pluck("people.x_id", :x_id, :direction, :occurred_at).each do |x_id, post, direction, time|
        touch(rows[x_id], direction.to_sym, post, time)
      end
      DirectMessage.where(partner_x_id: rows.keys).group(:partner_x_id).maximum(:occurred_at).each do |x_id, time|
        rows[x_id].dm_at = time
      end
      rows
    end
  end

  def touch(exchange, direction, post, time)
    exchange.public_send("#{direction}_posts") << post
    key = "#{direction}_at"
    exchange[key] = [ exchange[key], time ].compact.max
  end

  # Mutuals and pinned people, whose new posts are worth a look even without other reasons: { x_id => "Mutual" }.
  def watched
    @watched ||= begin
      mutual = Person.where(id: graph.following_ids_query).where(id: graph.follower_ids_query).where.not(x_id: nil).pluck(:x_id)
      pinned = Person.where(id: Pin.select(:person_id)).where.not(x_id: nil).pluck(:x_id)
      mutual.index_with { "Mutual" }.merge(pinned.index_with { "Pinned" }).except(@owner)
    end
  end

  def mutual?(person)
    graph.following?(person) && graph.follower?(person)
  end

  # Accounts that people around you reached lately while nothing between you and them was seen: { x_id => sources }.
  def network
    @network ||= begin
      circle = Person.where(id: graph.following_ids_query).where.not(x_id: nil).pluck(:x_id) | exchanges.keys
      counts = X::Interaction.where(source_x_id: circle, kind: %w[reply quote mention repost])
        .where.not(target_x_id: [ @owner, *exchanges.keys ])
        .where("COALESCE(occurred_at, observed_at) >= ?", NETWORK_WINDOW.ago)
        .group(:target_x_id).having("COUNT(DISTINCT source_x_id) >= ?", NETWORK_MIN)
        .order(Arel.sql("COUNT(DISTINCT source_x_id) DESC")).limit(LIMIT * 2).count("DISTINCT source_x_id")
      big = Person.where(x_id: counts.keys).where("followers_count > ?", BIG_ACCOUNT).pluck(:x_id) |
        X::Account.where(x_id: counts.keys).where("followers_count > ?", BIG_ACCOUNT).pluck(:x_id)
      counts.except(*big)
    end
  end

  def answered_ids
    ReplyEvent.where(direction: "outgoing").select(:target_x_id).distinct.pluck(:target_x_id) |
      Outreach::Target.pluck(:target_x_id) |
      X::SourcePost.where(author_x_id: @owner).where.not(parent_x_id: nil).pluck(:parent_x_id)
  end

  def parse_time(value)
    value.is_a?(String) ? Time.zone.parse("#{value} UTC") : value
  end
end
