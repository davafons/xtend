require "net/http"

class X::Client
  class Error < StandardError
    attr_reader :retry_at
    def initialize(message, retry_at: nil)
      @retry_at = retry_at
      super(message)
    end
  end
  API = "https://api.x.com"
  USER_FIELDS = "description,profile_image_url,profile_banner_url,location,url,entities,public_metrics,created_at,most_recent_tweet_id"

  def authorization_url(state:, verifier:)
    query = URI.encode_www_form(response_type: "code", client_id: X::Config.client_id,
      redirect_uri: X::Config.redirect_uri, scope: X::Config::SCOPES.join(" "),
      state: state, code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false), code_challenge_method: "S256")
    "https://x.com/i/oauth2/authorize?#{query}"
  end

  def exchange(code:, verifier:, redirect_uri:)
    token_request(grant_type: "authorization_code", code: code, code_verifier: verifier, redirect_uri: redirect_uri)
  end

  def refresh(refresh_token)
    token_request(grant_type: "refresh_token", refresh_token: refresh_token)
  end

  def identity(access_token)
    read = X::Read.fetch!(dataset: "identity", limit: 1) { identity_payload(access_token) }
    read.mark_applied!
    read.payload.fetch("data")
  end

  # Sign-in reads the identity before it knows the workspace, so it can't reserve the read first.
  # The caller records it with X::Read.record_sign_in! once the workspace is known.
  def identity_payload(access_token)
    X::Payload.identity(get("/2/users/me", access_token, "user.fields" => "profile_image_url"))
  end

  def page(access_token, owner_id:, dataset:, limit:, cursor: nil, since_id: nil, upper_bound: nil, parameters: {})
    query = {}
    case dataset
    when "followers", "following"
      path = "/2/users/#{owner_id}/#{dataset}"
      query = { max_results: limit, "user.fields" => X::Client::USER_FIELDS }
    when "own_posts", "mentions"
      path = "/2/users/#{owner_id}/#{dataset == 'own_posts' ? 'tweets' : 'mentions'}"
      query = { max_results: limit, "tweet.fields" => "author_id,created_at,lang,conversation_id,in_reply_to_user_id,referenced_tweets,public_metrics" }
      query[:end_time] = upper_bound.utc.iso8601 if upper_bound
      query[:since_id] = since_id if since_id
      query[:start_time] = parameters["start_time"] if parameters["start_time"]
      query[:exclude] = "retweets" if dataset == "own_posts"
    when "liked_posts", "bookmarks"
      path = "/2/users/#{owner_id}/#{dataset == 'liked_posts' ? 'liked_tweets' : 'bookmarks'}"
      query = { max_results: limit, "tweet.fields" => "author_id,created_at,lang,conversation_id,in_reply_to_user_id,referenced_tweets" }
    when "dm_events"
      path = "/2/dm_events"
      query = { max_results: limit, event_types: "MessageCreate", "dm_event.fields" => "id,event_type,created_at,dm_conversation_id,sender_id" }
    when "users"
      path = "/2/users"
      query = { ids: parameters.fetch("ids").join(","), "user.fields" => X::Client::USER_FIELDS }
    when "posts"
      path = "/2/tweets"
      query = { ids: parameters.fetch("ids").join(","), "tweet.fields" => "author_id,created_at,lang,conversation_id,in_reply_to_user_id,referenced_tweets,public_metrics" }
    else
      raise ArgumentError, "Unsupported X dataset"
    end
    query[:pagination_token] = cursor if cursor
    X::Payload.page(get(path, access_token, query), dataset: dataset)
  end

  private

  def get(path, access_token, query = {})
    path += "?#{URI.encode_www_form(query)}" if query.any?
    request = Net::HTTP::Get.new(path)
    request["Authorization"] = "Bearer #{access_token}"
    perform(request)
  end


  def token_request(form)
    request = Net::HTTP::Post.new("/2/oauth2/token")
    if X::Config.client_secret.present?
      request.basic_auth(X::Config.client_id, X::Config.client_secret)
    else
      form[:client_id] = X::Config.client_id
    end
    request.set_form_data(form)
    data = perform(request)
    unless data["access_token"].is_a?(String) && data["access_token"].present? && data["token_type"].to_s.casecmp?("bearer") && data["expires_in"].to_i.positive?
      raise Error, "X returned an incomplete token response. Reconnect X."
    end
    data
  end

  def perform(request)
    response = Net::HTTP.start("api.x.com", 443, use_ssl: true, open_timeout: 10, read_timeout: 15, write_timeout: 15) { |http| http.request(request) }
    unless response.is_a?(Net::HTTPSuccess)
      message = case response.code.to_i
      when 401 then "X authorization is no longer valid. Reconnect X."
      when 402, 403 then "X refused this read. Check the app's read permissions and API credit balance."
      when 400
        details = begin
          data = JSON.parse(response.body.to_s)
          [data["detail"], *Array(data["errors"]).filter_map { |item| item["message"] if item.is_a?(Hash) }].compact.join(" ").first(1000)
        rescue JSON::ParserError
          ""
        end
        "X rejected this request (HTTP 400). #{details}"
      when 429 then "X is rate limiting requests. Try again later."
      else "X could not complete this request (HTTP #{response.code}). Try again later."
      end
      reset = response["x-rate-limit-reset"].to_s
      retry_at = Time.at(reset.to_i) if response.code.to_i == 429 && reset.match?(/\A\d{1,12}\z/)
      raise Error.new(message, retry_at: retry_at)
    end
    raise Error, "X returned an oversized response." if response.body.to_s.bytesize > 2.megabytes
    data = JSON.parse(response.body)
    raise Error, "X returned an invalid response." unless data.is_a?(Hash)
    data
  rescue JSON::ParserError
    raise Error, "X returned an invalid response."
  rescue IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
    raise Error, "The connection to X failed. Try again later."
  end
end
