# Builds x.com GraphQL responses in the shapes the browser extension forwards.
module WebCaptureHelper
  def web_user(id, handle, layout: :current)
    if layout == :legacy
      { "__typename" => "User", "rest_id" => id, "legacy" => { "screen_name" => handle, "name" => handle.capitalize,
        "description" => "Builds #{handle} tools", "followers_count" => 120, "friends_count" => 80, "statuses_count" => 900,
        "profile_image_url_https" => "https://pbs.twimg.com/profile_images/#{id}/a_normal.jpg", "created_at" => "Wed Oct 10 20:19:24 +0000 2018" } }
    else
      { "__typename" => "User", "rest_id" => id, "core" => { "screen_name" => handle, "name" => handle.capitalize, "created_at" => "Wed Oct 10 20:19:24 +0000 2018" },
        "avatar" => { "image_url" => "https://pbs.twimg.com/profile_images/#{id}/a_normal.jpg" },
        "banner" => { "image_url" => "https://pbs.twimg.com/profile_banners/#{id}/1700000000" },
        "profile_bio" => { "description" => "Builds #{handle} tools",
          "entities" => { "url" => { "urls" => [ { "url" => "https://t.co/abc", "expanded_url" => "https://#{handle}.dev" } ] } } },
        "location" => { "location" => "Tokyo" }, "website" => { "url" => "https://t.co/abc" },
        "relationship_counts" => { "followers" => 120, "following" => 80 }, "tweet_counts" => { "tweets" => 900, "media_tweets" => 4 } }
    end
  end

  def web_tweet(id, author, text: "Shipping a tiny Rails app today", reply_to: nil, quoted: nil, reposted: nil, created: 1.hour.ago,
    likes: 10, views: "1500", mentions: [], media: [], urls: [], leading_mentions: [])
    prefix = leading_mentions.map { |user| "@#{user.dig('core', 'screen_name')} " }.join
    body = "#{prefix}#{text}#{mentions.map { |user| " @#{user.dig('core', 'screen_name')}" }.join}"
    entity_mentions = leading_mentions.each_with_index.map { |user, index| { "id_str" => user["rest_id"], "indices" => [ index, index + 1 ] } } +
      mentions.map { |user| { "id_str" => user["rest_id"], "indices" => [ prefix.length + 1, prefix.length + 2 ] } }
    legacy = { "full_text" => body, "created_at" => created.utc.strftime("%a %b %d %H:%M:%S +0000 %Y"), "user_id_str" => author["rest_id"],
      "conversation_id_str" => reply_to ? reply_to.fetch(:conversation, reply_to[:post]) : id, "lang" => "en", "reply_count" => 2,
      "favorite_count" => likes, "retweet_count" => 3, "quote_count" => 1, "bookmark_count" => 4,
      "display_text_range" => [ prefix.length, body.length ],
      "entities" => { "user_mentions" => entity_mentions, "urls" => urls.map { |url| { "expanded_url" => url } } },
      "in_reply_to_status_id_str" => reply_to&.dig(:post), "in_reply_to_user_id_str" => reply_to&.dig(:user),
      "quoted_status_id_str" => quoted&.dig("rest_id") }.compact
    legacy["extended_entities"] = { "media" => media.map { |type| { "type" => type } } } if media.any?
    legacy["retweeted_status_result"] = { "result" => reposted } if reposted
    tweet = { "__typename" => "Tweet", "rest_id" => id, "core" => { "user_results" => { "result" => author } }, "legacy" => legacy,
      "views" => { "count" => views, "state" => "EnabledWithCount" } }
    tweet["quoted_status_result"] = { "result" => quoted } if quoted
    tweet
  end

  def web_user_list(users)
    web_timeline([], users: users)
  end

  def web_timeline(tweets, promoted: [], users: [])
    entries = tweets.map { |tweet| entry("tweet-#{tweet['rest_id']}", "itemType" => "TimelineTweet", "tweet_results" => { "result" => tweet }) }
    entries += promoted.map { |tweet| entry("promoted-tweet-#{tweet['rest_id']}", "itemType" => "TimelineTweet", "promotedMetadata" => {}, "tweet_results" => { "result" => tweet }) }
    entries += users.map { |user| entry("user-#{user['rest_id']}", "itemType" => "TimelineUser", "user_results" => { "result" => user }) }
    { "data" => { "timeline" => { "instructions" => [ { "type" => "TimelineAddEntries", "entries" => entries } ] } } }
  end

  def web_response(operation, document, variables: {})
    { "operation" => operation, "variables" => variables, "body" => document.to_json }
  end

  def capture!(*responses, batch_key: SecureRandom.uuid, viewer: Current.workspace.owner_x_id)
    X::Capture.ingest!(batch_key: batch_key, viewer_x_id: viewer, responses: responses)
  end

  def owner_user
    web_user(Current.workspace.owner_x_id, "owner")
  end

  private

  def entry(id, item_content)
    { "entryId" => id, "content" => { "entryType" => "TimelineTimelineItem", "itemContent" => item_content } }
  end
end
