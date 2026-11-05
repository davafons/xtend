class XConfig
  SCOPES = %w[tweet.read users.read follows.read like.read bookmark.read dm.read offline.access].freeze
  DATASET_SCOPES = { "liked_posts" => "like.read", "bookmarks" => "bookmark.read", "dm_events" => "dm.read" }.freeze
  CALLBACK_PATH = "/x/connection/callback"

  def self.client_id
    values[:client_id]
  end

  def self.client_secret
    values[:client_secret]
  end

  def self.redirect_uri
    values[:redirect_uri]
  end

  def self.source
    return :environment if ENV["X_CLIENT_ID"].present?
    return :credentials if Rails.application.credentials.dig(:x, :client_id).present?
    XClientConfiguration.current ? :local : :none
  end

  def self.values
    case source
    when :environment
      {client_id: ENV["X_CLIENT_ID"], client_secret: ENV["X_CLIENT_SECRET"], redirect_uri: ENV["X_REDIRECT_URI"]}
    when :credentials
      config = Rails.application.credentials.fetch(:x)
      {client_id: config[:client_id], client_secret: config[:client_secret], redirect_uri: config[:redirect_uri]}
    when :local
      XClientConfiguration.current.values
    else
      {}
    end
  end

  def self.fingerprint
    Digest::SHA256.hexdigest([client_id, client_secret, redirect_uri].to_json)
  end

  def self.configured?
    client_id.present? && valid_redirect?
  end

  def self.valid_redirect?
    valid_redirect_uri?(redirect_uri.to_s)
  end

  def self.valid_redirect_uri?(value)
    uri = URI.parse(value)
    local_http = uri.scheme == "http" && %w[localhost 127.0.0.1 ::1 [::1]].include?(uri.host)
    uri.host.present? && (uri.scheme == "https" || local_http) && uri.path == CALLBACK_PATH && uri.query.nil? && uri.fragment.nil? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end

  def self.callback_origin
    return unless valid_redirect?
    uri = URI.parse(redirect_uri)
    "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.default_port == uri.port}"
  end
end
