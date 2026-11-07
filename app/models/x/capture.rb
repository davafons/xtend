# One batch of x.com GraphQL responses that the browser extension observed while the owner browsed.
# Captures cost nothing and make no X requests, but they only cover what was on screen: they never complete
# a follow snapshot or a like/bookmark backfill, and they never count as proof that something didn't happen.
#
# What a batch keeps:
# - Accounts: every profile it contains, in the X::Account directory.
# - People: added only when the owner showed interest (a visited profile, a liked or bookmarked post, or a reply
#   exchange with the owner). Other profiles only refresh existing people.
# - Posts: what the owner was shown (timeline, search, profile, list, thread entries), plus anything written by,
#   replying to, or quoting the owner's network (the owner and people in the CRM). Counts are saved per sighting.
# - The graph: replies, quotes, reposts, and body mentions between accounts; likes and reposts from engagement
#   lists; and follow edges from follow lists.
# - Your relationships: every account x.com shows says whether you follow it and whether it follows you. The
#   newest sighting per person corrects the latest follow snapshot for that person (see Follow::Graph), and your
#   own follow and unfollow clicks count the moment they happen. An unfollow is recorded in Follow review.
# - Your actions: likes, reposts, and bookmarks x.com marks on posts you were shown, and the ones you make.
class X::Capture
  class Rejected < StandardError; end
  MAX_RESPONSES = 100
  MAX_RESPONSE_BYTES = 4.megabytes
  ENGAGEMENT_KINDS = { likes: "like", bookmarks: "bookmark" }.freeze
  LISTED_PURPOSES = %i[discovery context likes bookmarks].freeze
  RESULT_KEYS = %i[posts people_added people_updated likes bookmarks accounts observations interactions follows relationships unfollows].freeze
  CLOCK_SKEW = 5.minutes

  Parsed = Struct.new(:payload, :purpose, :variables, :at)

  def self.ingest!(...) = new(...).ingest!

  def initialize(batch_key:, viewer_x_id:, responses:)
    raise Rejected, "Capture is disabled in the demo workspace." if Rails.configuration.x.demo
    raise Rejected, "Invalid batch key." unless batch_key.is_a?(String) && batch_key.match?(/\A[\w-]{16,64}\z/)
    @owner = Current.workspace.owner_x_id
    raise Rejected, "Connect your X account in the CRM first." if @owner.blank?
    raise Rejected, "The browser is signed in to a different X account than this workspace." unless viewer_x_id.to_s == @owner
    # An empty batch is the extension's connection test: it checks the token and the signed-in X account.
    raise Rejected, "Send at most #{MAX_RESPONSES} responses per batch." unless responses.is_a?(Array) && responses.size <= MAX_RESPONSES
    @batch_key = batch_key
    @now = Time.current
    @parsed = responses.filter_map { |response| parse(response) }
    @result = Hash.new(0).merge(responses: responses.size, ignored: responses.size - @parsed.size)
    @runs = {}
    @counts = Hash.new(0)
  end

  def ingest!
    posts = @parsed.map { |item| item.payload.posts }.reduce({}, :merge)
    profiles = @parsed.map { |item| item.payload.profiles }.reduce({}, :merge)
    details = @parsed.map { |item| item.payload.details }.reduce({}, :merge)
    @result[:skipped] = @parsed.sum { |item| item.payload.skipped }
    ActiveRecord::Base.transaction do
      save_accounts(profiles)
      save_profiles(profiles, addable_people(posts))
      saved = save_posts(posts, details)
      save_observations(saved, details)
      save_post_interactions(saved, posts, details)
      save_engagements(posts)
      save_engagement_lists(posts)
      save_follow_edges
      save_relationships(profiles)
      save_viewer_actions(posts)
      reconcile(saved)
      Draft.link_published! if posts.each_value.any? { |row| row["author_id"] == @owner }
      @runs.each { |key, run| run.update!(resource_count: @counts[key], page_limit: @counts[key].clamp(1, 1000)) }
    end
    [ :responses, :ignored, :skipped, :conflicts, *RESULT_KEYS ].index_with { |key| @result[key] }
  end

  private

  def parse(response)
    return unless response.is_a?(Hash) && X::WebPayload::OPERATIONS.key?(response["operation"])
    body = response["body"]
    return unless body.is_a?(String) && body.bytesize <= MAX_RESPONSE_BYTES
    variables = response["variables"].is_a?(Hash) ? response["variables"] : {}
    payload = X::WebPayload.new(response["operation"], JSON.parse(body))
    purpose = payload.purpose
    # Only the owner's own Likes page is evidence of the owner's likes.
    purpose = :context if purpose == :likes && variables["userId"].to_s != @owner
    Parsed.new(payload, purpose, variables, seen_at(response["at"]))
  rescue JSON::ParserError
    nil
  end

  # When the browser received the response, so a newer sighting always wins. Missing or implausible times
  # count as now.
  def seen_at(value)
    time = Time.zone.at(value / 1000.0) if value.is_a?(Numeric)
    time && time.between?(@now - 30.days, @now + CLOCK_SKEW) ? [ time, @now ].min : @now
  end

  def save_accounts(profiles)
    verified = @parsed.flat_map { |item| item.payload.verified_ids.to_a }.to_set
    rows = profiles.values.reject { |row| row["id"] == @owner }.map { |row| row.merge("verified" => verified.include?(row["id"])) }
    X::Account.observe!(rows, at: @now)
    @result[:accounts] += rows.size
  end

  def addable_people(posts)
    ids = Set.new
    @parsed.each do |item|
      case item.purpose
      when :likes, :bookmarks then ids.merge(item.payload.entry_post_ids.filter_map { |id| posts.dig(id, "author_id") })
      when :profile then ids.merge(item.payload.profiles.keys)
      end
    end
    posts.each_value do |row|
      ids << row["in_reply_to_user_id"] if row["author_id"] == @owner
      ids << row["author_id"] if row["in_reply_to_user_id"] == @owner
    end
    ids.delete(@owner)
    ids
  end

  def save_profiles(profiles, addable)
    known = Person.where(x_id: profiles.keys).pluck(:x_id).to_set
    profiles.each_value do |row|
      next if row["id"] == @owner || !(known.include?(row["id"]) || addable.include?(row["id"]))
      Person.resolve_profile!(Person.profile_from_x(row))
      @result[known.include?(row["id"]) ? :people_updated : :people_added] += 1
    end
    # Someone you just replied to may only be in the directory, from an earlier batch.
    X::Account.where(x_id: (addable - profiles.keys - known.to_a).to_a).find_each do |account|
      next if Person.exists?(x_id: account.x_id)
      Person.resolve_profile!(x_id: account.x_id, handle: account.handle, name: account.name, description: account.description)
      @result[:people_added] += 1
    end
  end

  def network
    @network ||= Person.where.not(x_id: nil).pluck(:x_id).to_set << @owner
  end

  def listed_ids
    @listed_ids ||= @parsed.select { |item| LISTED_PURPOSES.include?(item.purpose) }.flat_map { |item| item.payload.entry_post_ids }.to_set
  end

  # Keeps what the owner was shown and anything that touches the network; strangers talking to strangers inside
  # someone else's thread are dropped.
  def save_posts(posts, details)
    discovery = @parsed.select { |item| item.purpose == :discovery }.flat_map { |item| item.payload.entry_post_ids }.to_set
    posts.each_value.filter_map do |row|
      quoted_author = posts.dig(details.dig(row["id"], :quoted_x_id), "author_id")
      reposted_author = posts.dig(details.dig(row["id"], :reposted_x_id), "author_id")
      next unless listed_ids.include?(row["id"]) || [ row["author_id"], row["in_reply_to_user_id"], quoted_author, reposted_author ].any? { |id| network.include?(id) }
      purpose = discovery.include?(row["id"]) && row["author_id"] != @owner ? "discovery" : "context"
      X::SourcePost.capture!(row, run: run("posts", purpose), details: details[row["id"]], at: @now)
      @result[:posts] += 1
      row["id"]
    end
  end

  def save_observations(saved, details)
    saved = saved.to_set
    @parsed.each do |item|
      item.payload.entry_post_ids.uniq.each do |id|
        metrics = details[id]&.slice(*X::PostObservation::METRICS)&.compact
        next unless saved.include?(id) && metrics.present?
        X::PostObservation.record!(id, surface: item.payload.surface, metrics: metrics, at: @now)
        @result[:observations] += 1
      end
    end
  end

  def save_post_interactions(saved, posts, details)
    authors = posts.transform_values { |row| row["author_id"] }
    saved.each do |id|
      row = posts.fetch(id)
      detail = details[id] || {}
      author = row["author_id"]
      occurred = Time.iso8601(row["created_at"])
      if (quoted = detail[:quoted_x_id])
        interact("quote", author, authors[quoted] || X::SourcePost.find_by(x_id: quoted)&.author_x_id, id, quoted, occurred)
      end
      if (original = detail[:reposted_x_id])
        interact("repost", author, authors[original] || X::SourcePost.find_by(x_id: original)&.author_x_id, id, original, occurred)
      end
      Array(detail[:mention_ids]).each { |mentioned| interact("mention", author, mentioned, id, nil, occurred) unless mentioned == row["in_reply_to_user_id"] }
    end
  end

  def interact(kind, source, target, post, target_post, occurred)
    return unless X::Interaction.record!(kind: kind, source: source, target: target, post: post, target_post: target_post, occurred_at: occurred, at: @now)
    @result[:interactions] += 1
  end

  def save_engagements(posts)
    @parsed.each do |item|
      next unless (kind = ENGAGEMENT_KINDS[item.purpose])
      item.payload.entry_post_ids.each do |id|
        next unless (row = posts[id])
        state = Engagement.capture!(row, kind: kind, run: run(Engagement::KINDS.key(kind)))
        @result[kind.pluralize.to_sym] += 1 if state == :new
        interact("like", @owner, row["author_id"], id, id, nil) if kind == "like"
      end
    end
  end

  # "Liked by" lists are only shown on the owner's own posts; "Reposted by" lists on any post whose author is known.
  def save_engagement_lists(posts)
    @parsed.each do |item|
      next unless %i[likers reposters].include?(item.purpose)
      post = item.variables["tweetId"].to_s
      next unless post.match?(/\A\d{1,30}\z/)
      author = posts.dig(post, "author_id") || X::SourcePost.find_by(x_id: post)&.author_x_id
      author ||= @owner if item.purpose == :likers
      next unless author
      kind = item.purpose == :likers ? "like" : "repost"
      item.payload.entry_user_ids.each { |user| interact(kind, user, author, post, post, nil) }
    end
  end

  def save_follow_edges
    @parsed.each do |item|
      next unless item.purpose == :people
      user = item.variables["userId"].to_s
      next unless user.match?(/\A\d{1,30}\z/)
      following = item.payload.operation == "Following"
      item.payload.entry_user_ids.each do |listed|
        follower, followed = following ? [ user, listed ] : [ listed, user ]
        X::FollowEdge.record!(follower: follower, followed: followed, seen_on: item.payload.operation, at: @now)
        @result[:follows] += 1
      end
    end
  end

  # Applies relationship sightings and your follow clicks in the order the browser saw them. A sighting only
  # replaces an older one, so a delayed batch never undoes a newer answer.
  def save_relationships(profiles)
    events = @parsed.flat_map do |item|
      if X::WebPayload::FOLLOW_ACTIONS.include?(item.purpose)
        target = item.variables["user_id"].to_s.presence || item.payload.profiles.keys.first
        target.to_s.match?(/\A\d{1,30}\z/) ? [ [ item.at, target, { you_follow: item.purpose == :follow }, item.purpose ] ] : []
      else
        item.payload.relationships.map { |id, relationship| [ item.at, id, relationship, nil ] }
      end
    end
    events.reject! { |_, id| id == @owner }
    events.sort_by! { |at, *| at }
    events.each do |at, id, relationship, action|
      person = Person.find_by(x_id: id)
      if !person && relationship.values.any? && (row = profiles[id] || @parsed.lazy.filter_map { |item| item.payload.profiles[id] }.first)
        person = Person.resolve_profile!(Person.profile_from_x(row))
        @result[:people_added] += 1
      end
      record_follow_action(id, action, person, at) if action
      next unless person
      changes = relationship.each_with_object({}) do |(flag, value), memo|
        seen = person.public_send(:"#{flag}_seen_at")
        memo.merge!(flag => value, :"#{flag}_seen_at" => at) if seen.nil? || seen < at
      end
      next if changes.empty?
      person.update_columns(changes)
      @result[:relationships] += 1
    end
  end

  def record_follow_action(id, action, person, at)
    if action == :follow
      X::FollowEdge.record!(follower: @owner, followed: id, seen_on: "FollowCreate", at: at)
    else
      X::FollowEdge.where(follower_x_id: @owner, followed_x_id: id).delete_all
      if person
        Follow::Review.record!(person, "unfollowed")
        @result[:unfollows] += 1
      end
    end
  end

  # Likes, reposts, and bookmarks: the ones x.com marks on posts you were shown, and the ones you just made,
  # which only name the post.
  def save_viewer_actions(posts)
    @parsed.each do |item|
      item.payload.viewer_actions.each do |id, actions|
        next unless (row = posts[id])
        actions.each { |action| viewer_action(action, row) }
      end
      next unless (action = { liked: :like, reposted: :repost, bookmarked: :bookmark }[item.purpose])
      id = item.variables["tweet_id"].to_s
      next unless id.match?(/\A\d{1,30}\z/)
      row = posts[id] || X::SourcePost.find_by(x_id: id)&.then { |post| { "id" => post.x_id, "author_id" => post.author_x_id, "text" => post.body, "created_at" => post.published_at.iso8601 } }
      viewer_action(action, row) if row
    end
  end

  def viewer_action(action, row)
    case action
    when :like, :bookmark
      kind = action.to_s
      @result[kind.pluralize.to_sym] += 1 if Engagement.capture!(row, kind: kind, run: run(Engagement::KINDS.key(kind))) == :new
    when :repost
      interact("repost", @owner, row["author_id"], row["id"], row["id"], nil)
    end
  end

  # Reconciles only this batch and posts that reply to it. A conflicting reply is skipped, not fatal,
  # so one bad item cannot block every later batch.
  def reconcile(ids)
    X::SourcePost.where(x_id: ids).or(X::SourcePost.where(parent_x_id: ids)).includes(:x_sync_run).find_each do |post|
      ActiveRecord::Base.transaction(requires_new: true) { post.reconcile! }
    rescue ArgumentError, ActiveRecord::RecordInvalid
      @result[:conflicts] += 1
    end
  end

  def run(dataset, purpose = nil)
    key = [ dataset, purpose ].compact.join("-")
    @counts[key] += 1
    @runs[key] ||= X::SyncRun.find_or_create_by!(request_key: "capture-#{@batch_key}-#{key}") do |run|
      now = @now.change(usec: 0)
      run.assign_attributes(dataset: dataset, mode: "capture", status: "completed", owner_x_id: @owner,
        page_limit: 1, page_number: 1, upper_bound: now, finished_at: now, parameters: purpose ? { "purpose" => purpose } : {})
    end
  end
end
