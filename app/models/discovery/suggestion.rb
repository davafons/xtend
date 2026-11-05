class Discovery::Suggestion < ApplicationRecord
  include WorkspaceScoped
  class Invalid < StandardError; end
  validates :post_x_id, :source_url, presence: true
  scope :unresolved, -> { where(dismissed_at: nil).where.not(post_x_id: X::SourcePost.select(:x_id)) }

  def self.capture_links!(text)
    raise Invalid, "Paste up to 20 public post links, within 20 KB." unless text.is_a?(String) && text.bytesize <= 20_000
    urls = text.scan(%r{https?://[^\s<>"\)\]]+})
    raise Invalid, "Paste between 1 and 20 X post links." unless urls.size.between?(1, 20)
    parsed = urls.map do |url|
      uri = URI.parse(url)
      path = uri.path.match(%r{\A/(?:[A-Za-z0-9_]{1,15}|i/web)/status/(\d{1,30})/?\z})
      raise Invalid, "Use public x.com or twitter.com post links." unless %w[x.com www.x.com twitter.com www.twitter.com].include?(uri.host) && uri.userinfo.nil? && [80, 443].include?(uri.port) && path
      [path[1], "https://x.com#{uri.path}"]
    end
    transaction do
      parsed.each do |post_id, url|
        find_or_create_by!(post_x_id: post_id) { |row| row.source_url = url }
      end
    end
    parsed.map(&:first).uniq.size
  rescue URI::InvalidURIError, ActiveRecord::RecordInvalid
    raise Invalid, "One of the post links could not be imported. No links were saved."
  end

  def self.grok_prompt
    known = Post.where(published_at: 7.days.ago..).pluck(:x_id).first(100)
    <<~PROMPT
      Find up to 20 English public X posts from the last 7 days by builders where I can contribute a useful reply.
      My interests: #{Current.workspace.interests.join('; ')}.
      Prefer concrete questions, implementation tradeoffs, work in progress, and lessons from shipping.
      Avoid generic AI hype, engagement bait, follow-for-follow, pure promotion, crypto, and threads with more than 50 replies.
      Use public X search. Do not use my private X plugin, DMs, bookmarks, or home timeline.
      #{"Skip these post IDs, which I already have: #{known.join(', ')}." if known.any?}
      Report only what you observed. Do not invent URLs, IDs, dates, text, or follower counts; omit any field you did not see.
      If the twitter-crm MCP connector is available, call propose_candidate_posts instead of answering in text.
      Otherwise end your answer with one JSON code block in exactly this shape, so I can paste it into my CRM:
      {"format": "#{Grok::Intake::FORMAT}", "posts": [{"url": "https://x.com/handle/status/123", "author_handle": "handle", "author_name": "Name", "author_bio": "Bio as shown", "author_followers_count": 1200, "text": "The post text as shown", "published_at": "2026-11-05T09:30:00Z", "reply_count": 4, "language": "en", "match_reason": "One concrete reason I could add a useful reply"}]}
      Do not post, message, follow, or unfollow anyone.
    PROMPT
  end
end
