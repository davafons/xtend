# Normalizes a GraphQL response that x.com's own web app loaded into the same post and profile rows X::Payload
# produces for API reads. The browser extension forwards these responses; nothing here requests anything from X.
# X changes these shapes without notice, so unknown or malformed items are skipped rather than failing the batch.
class X::WebPayload
  OPERATIONS = {
    "HomeTimeline" => :discovery, "HomeLatestTimeline" => :discovery, "SearchTimeline" => :discovery,
    "UserTweets" => :discovery, "UserOriginalsTimeline" => :discovery, "UserTweetsAndReplies" => :discovery,
    "TweetDetail" => :context, "TweetResultByRestId" => :context,
    "Likes" => :likes, "Bookmarks" => :bookmarks,
    "UserByScreenName" => :profile, "UserByRestId" => :profile,
    "Followers" => :people, "Following" => :people, "BlueVerifiedFollowers" => :people, "FollowersYouKnow" => :people,
    "ListLatestTweetsTimeline" => :discovery, "UserMedia" => :discovery,
    "Favoriters" => :likers, "Retweeters" => :reposters,
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
    "TweetDetail" => "thread", "TweetResultByRestId" => "thread", "ListLatestTweetsTimeline" => "list",
    "Likes" => "likes", "Bookmarks" => "bookmarks"
  }.freeze
  COUNT_LIMIT = 0..2_000_000_000
  TIME_FORMAT = "%a %b %d %H:%M:%S %z %Y".freeze

  attr_reader :operation, :purpose, :posts, :profiles, :entry_post_ids, :entry_user_ids, :skipped, :details, :verified_ids,
    :relationships, :viewer_actions

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
    @skipped = 0
    # A follow or unfollow answers with the account in the older flat layout, and its relationship fields
    # still describe the moment before the change, so only the profile is kept.
    if FOLLOW_ACTIONS.include?(@purpose)
      document = document.is_a?(Hash) && document["id_str"].is_a?(String) ? { "__typename" => "User", "rest_id" => document["id_str"], "legacy" => document } : {}
    end
    walk(document)
    @relationships.clear if FOLLOW_ACTIONS.include?(@purpose)
  end

  def surface
    SURFACES.fetch(operation, "other")
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
      "text" => node.dig("note_tweet", "note_tweet_results", "result", "text") || legacy["full_text"],
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

  # Counts, media, links, and the accounts mentioned in the body. A repost's own counts belong to the original,
  # so reposts keep none. Leading @handles that X adds to a reply are the reply chain, not mentions.
  def post_details(node, legacy, original)
    details = { quoted_x_id: legacy["quoted_status_id_str"], reposted_x_id: original&.dig("rest_id") }
    return details.compact if original
    counts = { reply_count: legacy["reply_count"], like_count: legacy["favorite_count"], repost_count: legacy["retweet_count"],
      quote_count: legacy["quote_count"], bookmark_count: legacy["bookmark_count"], view_count: node.dig("views", "count") }
    counts.transform_values! { |value| self.class.send(:count, value) }
    media = Array(legacy.dig("extended_entities", "media") || legacy.dig("entities", "media")).filter_map { |item| item["type"] if item.is_a?(Hash) }
    urls = Array(legacy.dig("entities", "urls")).select { |url| url.is_a?(Hash) && url["expanded_url"].is_a?(String) && !url["expanded_url"].match?(%r{\Ahttps://(x|twitter)\.com/\w+/status/}) }
    body_start = Array(legacy["display_text_range"]).first.to_i
    mentions = Array(legacy.dig("entities", "user_mentions")).filter_map do |mention|
      mention["id_str"] if mention.is_a?(Hash) && mention["id_str"].to_s.match?(/\A\d{1,30}\z/) && Array(mention["indices"]).first.to_i >= body_start
    end
    details.merge(counts).merge(media_kinds: media.uniq.sort.join(",").presence, has_link: urls.any?, mention_ids: mentions.uniq)
  end

  def web_time(value)
    Time.strptime(value, TIME_FORMAT).utc.iso8601
  end
end
