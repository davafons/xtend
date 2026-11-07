# The owner's own copy of the timeline: saved posts from the network, newest or busiest first. Counts are the
# latest the capture saw, not live numbers.
class Network::Timeline
  PER_PAGE = 40
  WHO = { "network" => "Your people and you", "following" => "People you follow", "mutual" => "Mutuals", "seen" => "Everything you were shown" }.freeze
  KINDS = { "posts" => "Posts", "replies" => "Replies", "all" => "Posts and replies" }.freeze
  SORTS = { "latest" => "published_at DESC", "likes" => "like_count DESC NULLS LAST, published_at DESC",
    "views" => "view_count DESC NULLS LAST, published_at DESC", "replies" => "reply_count DESC NULLS LAST, published_at DESC" }.freeze
  PERIODS = { "7d" => 7.days, "30d" => 30.days, "90d" => 90.days, "all" => nil }.freeze

  attr_reader :who, :kind, :sort, :period, :tag, :person, :query, :page, :media

  def initialize(who: nil, kind: nil, sort: nil, period: nil, tag: nil, person: nil, query: nil, page: 1, media: nil)
    @who = WHO.key?(who) ? who : "network"
    @kind = KINDS.key?(kind) ? kind : "posts"
    @sort = SORTS.key?(sort) ? sort : "latest"
    @period = PERIODS.key?(period) ? period : "30d"
    @tag = tag.presence
    @person = person
    @query = query.to_s.strip.first(200).presence
    @media = media == "1"
    @page = [ page.to_i, 1 ].max
    @owner = Current.workspace.owner_x_id.to_s
  end

  def posts
    @posts ||= scope.order(Arel.sql(SORTS.fetch(sort))).offset((page - 1) * PER_PAGE).limit(PER_PAGE).to_a
  end

  def count
    @count ||= scope.count
  end

  def next_page?
    page * PER_PAGE < count
  end

  # Authors and quoted posts for the current page, so the view does no per-post queries.
  def people
    @people ||= Person.where(x_id: author_ids).includes(:tags).index_by(&:x_id)
  end

  def accounts
    @accounts ||= X::Account.where(x_id: author_ids - people.keys).index_by(&:x_id)
  end

  def quoted
    @quoted ||= X::SourcePost.where(x_id: posts.filter_map(&:quoted_x_id)).index_by(&:x_id)
  end

  def sightings
    @sightings ||= X::PostObservation.where(post_x_id: posts.map(&:x_id)).group(:post_x_id).count
  end

  def follow_graph
    @follow_graph ||= Follow::Graph.latest
  end

  private

  def author_ids
    @author_ids ||= (posts.map(&:author_x_id) + quoted.values.map(&:author_x_id) + posts.filter_map(&:reply_to_x_id)).uniq
  end

  def scope
    posts = X::SourcePost.where(repost: false)
    posts = posts.where(published_at: PERIODS.fetch(period).ago..) if PERIODS.fetch(period)
    posts = case kind
    when "posts" then posts.where(reply_to_x_id: nil)
    when "replies" then posts.where.not(reply_to_x_id: nil)
    else posts
    end
    posts = posts.where("body LIKE ?", "%#{X::SourcePost.sanitize_sql_like(query)}%") if query
    posts = posts.where.not(media_kinds: nil) if media
    return posts.where(author_x_id: person.x_id) if person
    people = Person.where.not(x_id: nil)
    people = people.tagged(tag) if tag
    graph = follow_graph
    case who
    when "following" then posts.where(author_x_id: people.where(id: graph.following_ids_query).select(:x_id))
    when "mutual" then posts.where(author_x_id: people.where(id: graph.following_ids_query).where(id: graph.follower_ids_query).select(:x_id))
    when "seen" then tag ? posts.where(author_x_id: people.select(:x_id)) : posts
    else tag ? posts.where(author_x_id: people.select(:x_id)) : posts.where(author_x_id: people.select(:x_id)).or(posts.where(author_x_id: @owner))
    end
  end
end
