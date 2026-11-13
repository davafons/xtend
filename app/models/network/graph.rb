# Who interacts with whom among the owner's people, built only from saved data. Nodes are the owner, people in
# the CRM, and optionally outside accounts that several people talk to. Links aggregate interactions (and
# optionally captured follow edges) per direction. Coverage is whatever was collected: a missing link is not proof
# that two accounts never interacted.
class Network::Graph
  PERIODS = { "30d" => 30.days, "90d" => 90.days, "1y" => 1.year, "all" => nil }.freeze
  SCOPES = { "all" => "Everyone in the CRM", "mutual" => "Mutuals", "following" => "People you follow", "followers" => "Your followers" }.freeze
  KINDS = (X::Interaction::KINDS + %w[follow]).freeze
  OUTSIDE_MIN_PEOPLE = 2
  OUTSIDE_LIMIT = 150

  attr_reader :period, :scope, :kinds, :tag, :include_owner, :outside

  def initialize(period: "90d", scope: "all", kinds: X::Interaction::KINDS, tag: nil, include_owner: true, outside: false)
    @period = PERIODS.key?(period) ? period : "90d"
    @scope = SCOPES.key?(scope) ? scope : "all"
    @kinds = Array(kinds).map(&:to_s) & KINDS
    @kinds = X::Interaction::KINDS.dup if @kinds.empty?
    @tag = tag.presence
    @include_owner = include_owner
    @outside = outside
    @owner = Current.workspace.owner_x_id.to_s
  end

  def nodes
    build
    @nodes
  end

  def links
    build
    @links
  end

  # Members of the chosen scope with no link in this view.
  def isolated_count
    build
    @isolated_count
  end

  def as_json(*)
    { nodes: nodes, links: links, isolated: isolated_count, owner: @owner }
  end

  private

  def build
    return if @links
    people = scoped_people.to_a
    ids = people.map(&:x_id).to_set
    ids << @owner if include_owner
    outside_accounts = outside ? outside_accounts_for(ids) : {}
    all_ids = ids | outside_accounts.keys
    edges = interaction_counts(all_ids)
    follow_counts(all_ids).each { |pair, counts| edges[pair] = edges.fetch(pair, {}).merge(counts) } if kinds.include?("follow")
    # Outside accounts only matter through people: links between two outside accounts are dropped.
    edges.select! { |(source, target), _| ids.include?(source) || ids.include?(target) }
    @links = edges.map { |(source, target), counts| { source: source, target: target, kinds: counts, weight: counts.values.sum } }
    linked = @links.flat_map { |link| [ link[:source], link[:target] ] }.to_set
    degree = Hash.new(0)
    @links.each { |link| degree[link[:source]] += link[:weight]; degree[link[:target]] += link[:weight] }
    graph = Follow::Graph.latest
    @nodes = people.select { |person| linked.include?(person.x_id) }.map { |person| person_node(person, graph, degree) }
    @nodes << owner_node(degree) if include_owner && linked.include?(@owner)
    @nodes += outside_accounts.values.select { |account| linked.include?(account.x_id) }.map { |account| account_node(account, degree) }
    @isolated_count = people.count { |person| !linked.include?(person.x_id) }
  end

  def scoped_people
    people = Person.where.not(x_id: nil).includes(:tags, :pin)
    people = people.tagged(tag) if tag
    graph = Follow::Graph.latest
    following = graph.following_ids_query
    followers = graph.follower_ids_query
    case scope
    when "mutual" then people.where(id: following).where(id: followers)
    when "following" then people.where(id: following)
    when "followers" then people.where(id: followers)
    else people
    end
  end

  def since
    PERIODS.fetch(period)&.ago
  end

  # { [source, target] => { kind => count } }
  def interaction_counts(ids)
    interaction_kinds = kinds & X::Interaction::KINDS
    return {} if interaction_kinds.empty?
    scope = X::Interaction.where(kind: interaction_kinds, source_x_id: ids.to_a, target_x_id: ids.to_a)
    scope = scope.where("COALESCE(occurred_at, observed_at) >= ?", since) if since
    counts = Hash.new { |hash, key| hash[key] = {} }
    scope.group(:source_x_id, :target_x_id, :kind).count.each { |(source, target, kind), count| counts[[ source, target ]][kind] = count }
    counts
  end

  def follow_counts(ids)
    counts = {}
    X::FollowEdge.where(follower_x_id: ids.to_a, followed_x_id: ids.to_a).pluck(:follower_x_id, :followed_x_id).each do |source, target|
      counts[[ source, target ]] = { "follow" => 1 }
    end
    counts
  end

  # Accounts outside the CRM that at least two people in scope interacted with, busiest first.
  def outside_accounts_for(ids)
    scope = X::Interaction.where(kind: kinds & X::Interaction::KINDS, source_x_id: ids.to_a).where.not(target_x_id: Person.where.not(x_id: nil).select(:x_id)).where.not(target_x_id: @owner)
    scope = scope.where("COALESCE(occurred_at, observed_at) >= ?", since) if since
    busy = scope.group(:target_x_id).having("COUNT(DISTINCT source_x_id) >= ?", OUTSIDE_MIN_PEOPLE).order(Arel.sql("COUNT(DISTINCT source_x_id) DESC")).limit(OUTSIDE_LIMIT).count("DISTINCT source_x_id")
    X::Account.where(x_id: busy.keys).index_by(&:x_id)
  end

  def person_node(person, graph, degree)
    state = person.follow_state(graph)
    { id: person.x_id, handle: person.handle, name: person.name, avatar: person.avatar_image_url, person_id: person.id,
      relation: relation(state), follow_state: state, tags: person.tags.map(&:name), pinned: person.pin.present?,
      followers: person.followers_count, weight: degree[person.x_id] }
  end

  def owner_node(degree)
    connection = X::Connection.current
    { id: @owner, handle: connection&.username || "you", name: "You", avatar: connection&.avatar_image_url, owner: true, relation: "owner", weight: degree[@owner] }
  end

  def account_node(account, degree)
    { id: account.x_id, handle: account.handle, name: account.name, avatar: account.avatar_image_url, outside: true,
      relation: "outside", followers: account.followers_count, weight: degree[account.x_id] }
  end

  def relation(state)
    case state
    when "Mutual" then "both"
    when "You follow", "You follow | follow-back unknown" then "you"
    when "Follows you", "Observed follower" then "them"
    else "none"
    end
  end
end
