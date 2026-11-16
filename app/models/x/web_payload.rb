# Normalizes a GraphQL response that x.com's own web app loaded into the same post and profile rows X::Payload
# produces for API reads. The browser extension forwards these responses; nothing here requests anything from X.
# X changes these shapes without notice, so unknown or malformed items are skipped rather than failing the batch.
class X::WebPayload
  OPERATIONS = {
    "HomeTimeline" => :discovery, "HomeLatestTimeline" => :discovery, "SearchTimeline" => :discovery,
    "UserTweets" => :discovery, "UserOriginalsTimeline" => :discovery, "UserTweetsAndReplies" => :discovery,
    "UserRepliesTimeline" => :discovery, "UserRepostsTimeline" => :discovery, "UserVideoTimeline" => :discovery,
    "TweetDetail" => :context, "TweetResultByRestId" => :context,
    "Likes" => :likes, "Bookmarks" => :bookmarks,
    "UserByScreenName" => :profile, "UserByRestId" => :profile, "UsersByRestIds" => :context,
    "Followers" => :people, "Following" => :people, "BlueVerifiedFollowers" => :people, "FollowersYouKnow" => :people,
    "ListLatestTweetsTimeline" => :discovery, "UserMedia" => :discovery,
    "Favoriters" => :likers, "Retweeters" => :reposters,
    # A profile hover card's "Followed by" line: accounts you follow who follow that account. A REST call in the
    # older flat layout; the extension names it.
    "FollowingFollowers" => :people,
    # Your notifications: replies and mentions as posts, plus who liked or reposted your posts and who followed you.
    "NotificationsTimeline" => :notifications,
    # Your own actions. A new post or reply comes back in full; a like, repost, or bookmark only names the post.
    "CreateTweet" => :context, "CreateNoteTweet" => :context,
    "FavoriteTweet" => :liked, "CreateRetweet" => :reposted, "CreateBookmark" => :bookmarked,
    # Following and unfollowing are REST calls, not GraphQL; the extension names them.
    "FollowCreate" => :follow, "FollowDestroy" => :unfollow
  }.freeze
  FOLLOW_ACTIONS = %i[follow unfollow].freeze
  # Where a post was seen, for X::PostObservation.
  SURFACES = {
    "HomeTimeline" => "home", "HomeLatestTimeline" => "home", "SearchTimeline" => "search",
    "UserTweets" => "profile", "UserOriginalsTimeline" => "profile", "UserTweetsAndReplies" => "profile", "UserMedia" => "profile",
    "UserRepliesTimeline" => "profile", "UserRepostsTimeline" => "profile", "UserVideoTimeline" => "profile",
    "NotificationsTimeline" => "notifications",
    "TweetDetail" => "thread", "TweetResultByRestId" => "thread", "ListLatestTweetsTimeline" => "list",
    "Likes" => "likes", "Bookmarks" => "bookmarks"
  }.freeze
  # Notification types that name who acted on your posts or account. Others (new-post alerts, archive notices,
  # likes on your reposts or on posts you were mentioned in) say nothing about your own posts and are skipped.
  NOTIFICATION_KINDS = {
    "users_liked_your_tweet" => "like", "user_liked_multiple_tweets" => "like",
    "users_retweeted_your_tweet" => "repost",
    "users_followed_you" => "follow", "follow_from_recommended_user" => "follow"
  }.freeze
  Notification = Data.define(:kind, :actor_ids, :post_ids, :at)
  COUNT_LIMIT = 0..2_000_000_000
  TIME_FORMAT = "%a %b %d %H:%M:%S %z %Y".freeze

  attr_reader :operation, :purpose, :posts, :profiles, :entry_post_ids, :entry_user_ids, :skipped, :details, :verified_ids,
    :relationships, :viewer_actions, :bottom_cursor, :notifications

  def initialize(operation, document)
    @operation = operation
    @purpose = OPERATIONS.fetch(operation)
    @posts = {}
    @profiles = {}
    @entry_post_ids = []
    @entry_user_ids = []
    @details = {}
    @verified_ids = Set.new
    @relationships = {}
    @viewer_actions = {}
    @notifications = []
    @skipped = 0
    # A follow or unfollow answers with the account in the older flat layout, and its relationship fields
    # still describe the moment before the change, so only the profile is kept.
    if FOLLOW_ACTIONS.include?(@purpose)
      document = document.is_a?(Hash) && document["id_str"].is_a?(String) ? flat_user(document) : {}
    end
    if operation == "FollowingFollowers"
      users = document.is_a?(Hash) && document["users"].is_a?(Array) ? document["users"].select { |user| user.is_a?(Hash) && user["id_str"].is_a?(String) } : []
      @entry_user_ids = users.map { |user| user["id_str"] }
      document = users.map { |user| flat_user(user) }
    end
    walk(document)
    @relationships.clear if FOLLOW_ACTIONS.include?(@purpose)
  end

  def surface
    SURFACES.fetch(operation, "other")
  end

  # A follow list page that is the last one: no accounts, a cursor that points nowhere, or X saying the list ends.
  def list_end?
    @terminated || entry_user_ids.empty? || bottom_cursor.nil? || bottom_cursor.start_with?("0|")
  end

  private_class_method def self.count(value)
    number = value.is_a?(String) && value.match?(/\A\d+\z/) ? value.to_i : value
    number if number.is_a?(Integer) && COUNT_LIMIT.cover?(number)
  end

  private

  def walk(node)
    case node
    when Array then node.each { |child| walk(child) }
    when Hash
      collect_entry(node["itemContent"]) if node["itemContent"].is_a?(Hash)
      collect_notification(node) if node.dig("itemContent", "__typename") == "TimelineNotification"
      # Where the next page of a list starts. X ends a list with a cursor that starts with "0|".
      @bottom_cursor = node["value"] if node["cursorType"] == "Bottom" && node["value"].is_a?(String)
      @terminated = true if node["type"] == "TimelineTerminateTimeline" && node["direction"] == "Bottom"
      case node["__typename"]
      when "Tweet" then add_post(node)
      when "User" then add_profile(node)
      when "TweetWithVisibilityResults" then add_post(node["tweet"]) if node["tweet"].is_a?(Hash)
      end
      node.each_value { |child| walk(child) if child.is_a?(Hash) || child.is_a?(Array) }
    end
  end

  # Timeline items are what the page actually listed; quoted, retweeted, and embedded posts are only context.
  def collect_entry(content)
    return if content["promotedMetadata"]
    case content["itemType"]
    when "TimelineTweet"
      tweet = unwrap(content.dig("tweet_results", "result"))
      @entry_post_ids << tweet["rest_id"] if tweet&.dig("rest_id").is_a?(String)
    when "TimelineUser"
      user = content.dig("user_results", "result")
      @entry_user_ids << user["rest_id"] if user.is_a?(Hash) && user["rest_id"].is_a?(String)
    end
  end

  # One notification: its type is on the entry, the accounts and posts it names are in its template, and its time
  # is when the newest of those actions happened.
  def collect_notification(content)
    kind = NOTIFICATION_KINDS[content.dig("clientEventInfo", "element")]
    item = content["itemContent"]
    template = item["template"]
    return unless kind && template.is_a?(Hash)
    actors = Array(template["from_users"]).filter_map { |ref| ref.dig("user_results", "result", "rest_id") if ref.is_a?(Hash) }
    posts = Array(template["target_objects"]).filter_map { |ref| unwrap(ref.dig("tweet_results", "result"))&.dig("rest_id") if ref.is_a?(Hash) }
    at = Time.iso8601(item["timestamp_ms"]) rescue nil
    actors.select! { |id| id.is_a?(String) && id.match?(/\A\d{1,30}\z/) }
    posts.select! { |id| id.is_a?(String) && id.match?(/\A\d{1,30}\z/) }
    return if actors.empty? || (kind != "follow" && posts.empty?)
    @notifications << Notification.new(kind: kind, actor_ids: actors.uniq, post_ids: posts.uniq, at: at)
  end

  # The older flat user layout, as REST answers send it, in the GraphQL shape add_profile reads.
  def flat_user(user)
    { "__typename" => "User", "rest_id" => user["id_str"], "legacy" => user }
  end

  def unwrap(result)
    return unless result.is_a?(Hash)
    result["__typename"] == "TweetWithVisibilityResults" ? result["tweet"] : result
  end

  def add_post(node)
    legacy = node["legacy"]
    return unless node["rest_id"].is_a?(String) && legacy.is_a?(Hash)
    references = []
    references << { "type" => "replied_to", "id" => legacy["in_reply_to_status_id_str"] } if legacy["in_reply_to_status_id_str"]
    references << { "type" => "quoted", "id" => legacy["quoted_status_id_str"] } if legacy["quoted_status_id_str"]
    if (original = unwrap(legacy.dig("retweeted_status_result", "result")))
      references << { "type" => "retweeted", "id" => original["rest_id"] }
    end
    row = { "id" => node["rest_id"], "author_id" => legacy["user_id_str"] || node.dig("core", "user_results", "result", "rest_id"),
      "text" => post_text(node, legacy),
      "created_at" => web_time(legacy["created_at"]), "lang" => legacy["lang"],
      "conversation_id" => legacy["conversation_id_str"], "in_reply_to_user_id" => legacy["in_reply_to_user_id_str"],
      "public_metrics" => ({ "reply_count" => legacy["reply_count"] } if legacy["reply_count"].is_a?(Integer)),
      "referenced_posts" => references }.compact
    @posts[row["id"]] = X::Payload.post(row)
    @details[row["id"]] = post_details(node, legacy, original)
    # What the signed-in viewer did to this post, as x.com reports it with every post it shows.
    actions = { like: legacy["favorited"], repost: legacy["retweeted"], bookmark: legacy["bookmarked"] }.select { |_, value| value == true }.keys
    @viewer_actions[row["id"]] = actions if actions.any?
  rescue KeyError, ArgumentError, TypeError, NoMethodError
    @skipped += 1
  end

  # Profiles appear in two layouts: the current one splits `core`, `avatar`, `banner`, `profile_bio`, `location`,
  # `website`, `relationship_counts`, and `tweet_counts`; older responses keep everything in `legacy`.
  def add_profile(node)
    legacy = node["legacy"].is_a?(Hash) ? node["legacy"] : {}
    core = node["core"].is_a?(Hash) ? node["core"] : {}
    return unless node["rest_id"].is_a?(String) && (core["screen_name"] || legacy["screen_name"])
    # `website.url` is a t.co short link; the entities carry the address the owner of the profile typed.
    website = node.dig("profile_bio", "entities", "url", "urls", 0, "expanded_url") || legacy.dig("entities", "url", "urls", 0, "expanded_url")
    row = { "id" => node["rest_id"], "username" => core["screen_name"] || legacy["screen_name"],
      "name" => core["name"] || legacy["name"],
      "description" => node.dig("profile_bio", "description") || legacy["description"],
      "profile_image_url" => node.dig("avatar", "image_url") || legacy["profile_image_url_https"],
      "profile_banner_url" => node.dig("banner", "image_url") || legacy["profile_banner_url"],
      "location" => node.dig("location", "location") || legacy["location"],
      "entities" => ({ "url" => { "urls" => [ { "expanded_url" => website } ] } } if website),
      "public_metrics" => { "followers_count" => node.dig("relationship_counts", "followers") || legacy["followers_count"],
        "following_count" => node.dig("relationship_counts", "following") || legacy["friends_count"],
        "tweet_count" => node.dig("tweet_counts", "tweets") || legacy["statuses_count"] },
      "created_at" => (web_time(core["created_at"] || legacy["created_at"]) rescue nil) }.compact
    @profiles[row["id"]] = X::Payload.profile(row)
    @verified_ids << row["id"] if node["is_blue_verified"] == true || legacy["verified"] == true
    # The viewer's relationship to this account. Only explicit true or false counts; a missing field says nothing.
    perspective = node["relationship_perspectives"].is_a?(Hash) ? node["relationship_perspectives"] : legacy
    relationship = { you_follow: perspective["following"], follows_you: perspective["followed_by"] }.select { |_, value| value == true || value == false }
    @relationships[row["id"]] = relationship if relationship.any?
  rescue KeyError, ArgumentError, TypeError, NoMethodError
    @skipped += 1
  end

  # Counts, media (kinds and what to draw), links, and the accounts mentioned in the body. A repost's own counts belong to the original,
  # so reposts keep none. Leading @handles that X adds to a reply are the reply chain, not mentions.
  def post_details(node, legacy, original)
    details = { quoted_x_id: legacy["quoted_status_id_str"], reposted_x_id: original&.dig("rest_id") }
    return details.compact if original
    counts = { reply_count: legacy["reply_count"], like_count: legacy["favorite_count"], repost_count: legacy["retweet_count"],
      quote_count: legacy["quote_count"], bookmark_count: legacy["bookmark_count"], view_count: node.dig("views", "count") }
    counts.transform_values! { |value| self.class.send(:count, value) }
    items = legacy.dig("extended_entities", "media") || legacy.dig("entities", "media")
    media = Array(items).filter_map { |item| item["type"] if item.is_a?(Hash) }
    entities = post_entities(node, legacy)
    urls = Array(entities["urls"]).select { |url| url.is_a?(Hash) && url["expanded_url"].is_a?(String) && !url["expanded_url"].match?(%r{\Ahttps://(x|twitter)\.com/\w+/status/}) }
    body_start = Array(legacy["display_text_range"]).first.to_i
    mentions = Array(entities["user_mentions"]).filter_map do |mention|
      mention["id_str"] if mention.is_a?(Hash) && mention["id_str"].to_s.match?(/\A\d{1,30}\z/) && Array(mention["indices"]).first.to_i >= body_start
    end
    details.merge(counts).merge(media_kinds: media.uniq.sort.join(",").presence, media: X::Media.parse(items), has_link: urls.any?, mention_ids: mentions.uniq)
  end

  # The text as x.com shows it: a long post's full text, links pointing where they go instead of t.co, no trailing
  # link to the post's own media or quoted post (unless the post is only media), and no HTML escapes. An article
  # shows its title and preview.
  def post_text(node, legacy)
    article = node.dig("article", "article_results", "result")
    if article.is_a?(Hash) && article["title"].is_a?(String)
      return [ article["title"], article["preview_text"] ].select { |part| part.is_a?(String) && part.present? }.join("\n\n")
    end
    note = node.dig("note_tweet", "note_tweet_results", "result", "text")
    text = (note || legacy["full_text"]).to_s
    entities = post_entities(node, legacy)
    quoted = legacy["quoted_status_id_str"]
    Array(entities["urls"]).each do |url|
      next unless url.is_a?(Hash) && url["url"].is_a?(String) && url["expanded_url"].is_a?(String)
      own_quote = quoted && url["expanded_url"].match?(%r{\Ahttps://(x|twitter)\.com/\w+/status/#{quoted}\b})
      text = text.gsub(url["url"], own_quote ? "" : url["expanded_url"])
    end
    media = Array(legacy.dig("entities", "media")).select { |item| item.is_a?(Hash) && item["url"].is_a?(String) }
    media.each { |item| text = text.gsub(item["url"], "") }
    text = CGI.unescapeHTML(text).strip
    # A post that is only media keeps a link to it, since a post needs some text.
    text.presence || media.first&.then { |item| item["expanded_url"] || item["url"] }.to_s
  end

  # A long post's links and mentions are in its own entity set; the legacy entities only cover the first 280 characters.
  def post_entities(node, legacy)
    note = node.dig("note_tweet", "note_tweet_results", "result", "entity_set")
    note.is_a?(Hash) ? note : (legacy["entities"].is_a?(Hash) ? legacy["entities"] : {})
  end

  def web_time(value)
    Time.strptime(value, TIME_FORMAT).utc.iso8601
  end
end
