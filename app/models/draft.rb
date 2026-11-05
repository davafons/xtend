class Draft < ApplicationRecord
  STATUSES = { "idea" => "Ideas", "drafting" => "Drafting", "ready" => "Ready", "posted" => "Posted" }.freeze
  LIMIT = 280
  URL = %r{https?://\S+}
  PART_SEPARATOR = /^\s*---\s*$/

  validates :status, inclusion: { in: STATUSES.keys }
  validates :body, length: { maximum: 25_000 }
  validates :topic, length: { maximum: 120 }
  validates :inspiration_url, format: { with: %r{\Ahttps://(?:www\.)?(?:x|twitter)\.com/\S+\z} }, allow_blank: true
  validate { errors.add(:base, "Write something, or add a topic or note") if body.blank? && topic.blank? && notes.blank? }

  scope :in_status, ->(status) { where(status: status) }
  scope :recent, -> { order(updated_at: :desc) }

  # X weights most Latin text as 1 and CJK, emoji and other scripts as 2; links count as 23.
  def self.weighted_length(text)
    text.to_s.unicode_normalize(:nfc).gsub(URL, "x" * 23).each_char.sum do |char|
      code = char.ord
      code <= 4351 || code.between?(8192, 8205) || code.between?(8208, 8223) || code.between?(8242, 8247) ? 1 : 2
    end
  end

  def self.link_published!
    owner = Workspace.current.owner_x_id
    return if owner.blank?
    where(status: %w[ready posted], posted_x_id: nil).find_each do |draft|
      key = draft.match_key
      next if key.size < 20
      post = XSourcePost.where(author_x_id: owner, repost: false).where.not(x_id: where.not(posted_x_id: nil).select(:posted_x_id))
        .order(published_at: :desc).find { |candidate| normalize(candidate.body).start_with?(key) }
      draft.update!(status: "posted", posted_x_id: post.x_id, posted_at: post.published_at) if post
    end
  end

  def self.normalize(text)
    CGI.unescapeHTML(text.to_s).gsub(URL, "").squish.downcase
  end

  def parts
    body.to_s.split(PART_SEPARATOR).map(&:strip).reject(&:blank?)
  end

  def thread?
    parts.size > 1
  end

  def part_lengths
    parts.map { |part| self.class.weighted_length(part) }
  end

  def over_limit?
    part_lengths.any? { |length| length > LIMIT }
  end

  def title
    parts.first.to_s.lines.first.to_s.strip.presence || topic
  end

  def match_key
    self.class.normalize(parts.first).first(80)
  end

  def intent_url
    "https://x.com/intent/post?text=#{ERB::Util.url_encode(parts.first.to_s)}"
  end

  def posted_url
    "https://x.com/i/status/#{posted_x_id}" if posted_x_id
  end

  def next_status
    STATUSES.keys[STATUSES.keys.index(status) + 1]
  end

  def previous_status
    index = STATUSES.keys.index(status)
    STATUSES.keys[index - 1] if index.positive?
  end
end
