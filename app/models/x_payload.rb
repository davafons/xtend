class XPayload
  def self.identity(document)
    {"data" => profile(document.fetch("data"))}
  rescue KeyError, ArgumentError, TypeError, NoMethodError
    raise XClient::Error, "X returned an incomplete account identity."
  end

  def self.page(document, dataset:)
    raise ArgumentError if document["includes"].present?
    rows = document.fetch("data", [])
    meta = document.fetch("meta", {})
    raise ArgumentError unless rows.is_a?(Array) && meta.is_a?(Hash)
    unless document.key?("data")
      raise ArgumentError unless meta["result_count"] == 0 || document["errors"].present?
    end
    if meta.key?("result_count")
      raise ArgumentError unless meta["result_count"].is_a?(Integer) && meta["result_count"] == rows.size
    end
    rows = rows.map do |row|
      if %w[followers following users].include?(dataset) then profile(row)
      elsif dataset == "dm_events" then dm_event(row)
      else post(row)
      end
    end
    cursor = meta["next_token"]
    raise ArgumentError if cursor && (!cursor.is_a?(String) || cursor.bytesize > 4096 || cursor.empty?)
    {"data" => rows, "meta" => meta.slice("next_token", "newest_id", "oldest_id", "result_count"),
      "partial_errors" => document["errors"].present?}
  rescue KeyError, ArgumentError, TypeError, NoMethodError
    raise XClient::Error, "X returned incomplete source data. Existing CRM data is preserved."
  end

  def self.profile(row)
    id = numeric_id(row.fetch("id"))
    handle = row.fetch("username")
    name = row.fetch("name", handle)
    raise ArgumentError unless handle.is_a?(String) && handle.match?(/\A[A-Za-z0-9_]{1,15}\z/) && name.is_a?(String) && name.present? && name.bytesize <= 1000
    description = row["description"]
    raise ArgumentError if description && (!description.is_a?(String) || description.bytesize > 10_000)
    metrics = row["public_metrics"].is_a?(Hash) ? row["public_metrics"] : {}
    website = Array(row.dig("entities", "url", "urls")).first
    website = website["expanded_url"] if website.is_a?(Hash)
    created = Time.iso8601(row["created_at"]).iso8601 rescue nil
    {"id" => id, "username" => handle, "name" => name, "description" => description,
      "profile_image_url" => image_url(row["profile_image_url"]), "profile_banner_url" => image_url(row["profile_banner_url"]),
      "location" => (row["location"] if row["location"].is_a?(String) && row["location"].bytesize <= 300),
      "website_url" => (website if website.is_a?(String) && website.bytesize <= 500 && website.match?(%r{\Ahttps?://[^\s<>"]+\z})),
      "followers_count" => count(metrics["followers_count"]), "following_count" => count(metrics["following_count"]),
      "posts_count" => count(metrics["tweet_count"]), "created_at" => created}.compact
  end

  def self.image_url(value)
    value if value.is_a?(String) && value.bytesize <= 500 && value.match?(%r{\Ahttps://pbs\.twimg\.com/[A-Za-z0-9_\-./]+\z})
  end

  def self.count(value)
    value if value.is_a?(Integer) && value.between?(0, 2_000_000_000)
  end

  def self.post(row)
    result = {"id" => numeric_id(row.fetch("id")), "author_id" => numeric_id(row.fetch("author_id")),
      "text" => row.fetch("text"), "created_at" => Time.iso8601(row.fetch("created_at")).iso8601,
      "lang" => row["lang"], "referenced_posts" => []}
    raise ArgumentError unless result["text"].is_a?(String) && result["text"].bytesize <= 100_000
    raise ArgumentError if result["lang"] && !result["lang"].is_a?(String)
    %w[in_reply_to_user_id conversation_id].each { |key| result[key] = numeric_id(row[key]) if row[key] }
    if row.dig("public_metrics", "reply_count")
      count = row.fetch("public_metrics").fetch("reply_count")
      raise ArgumentError unless count.is_a?(Integer) && count.between?(0, 2_147_483_647)
      result["reply_count"] = count
    end
    references = row.fetch("referenced_posts", row.fetch("referenced_tweets", []))
    raise ArgumentError unless references.is_a?(Array)
    result["referenced_posts"] = references.map do |ref|
      raise ArgumentError unless %w[replied_to quoted retweeted].include?(ref.fetch("type"))
      {"id" => numeric_id(ref.fetch("id")), "type" => ref.fetch("type")}
    end
    result
  end

  # Keeps sender, conversation, and time only; message text and attachments are dropped before storage.
  def self.dm_event(row)
    raise ArgumentError unless row.fetch("event_type") == "MessageCreate"
    conversation = row.fetch("dm_conversation_id")
    raise ArgumentError unless conversation.is_a?(String) && conversation.match?(/\A\d{1,30}(-\d{1,30})?\z/)
    {"id" => numeric_id(row.fetch("id")), "conversation_id" => conversation, "sender_id" => numeric_id(row.fetch("sender_id")),
      "created_at" => Time.iso8601(row.fetch("created_at")).iso8601}
  end

  def self.numeric_id(value)
    raise ArgumentError unless value.is_a?(String) && value.match?(/\A\d{1,30}\z/)
    value
  end
end
