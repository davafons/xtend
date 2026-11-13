class Draft < ApplicationRecord
  include WorkspaceScoped
  STATUSES = { "idea" => "Ideas", "drafting" => "Drafting", "ready" => "Ready", "posted" => "Posted" }.freeze
  LIMIT = 280
  URL = %r{https?://\S+}
  PART_SEPARATOR = /^\s*---\s*$/
  SOURCES = %w[owner ai].freeze
  MAX_ALTERNATIVES = 20

  has_many :alternatives, -> { order(:created_at, :id) }, class_name: "Draft::Alternative", dependent: :destroy
  has_many :revisions, class_name: "Draft::Revision", dependent: :destroy

  # Who is writing this change: the owner in the app, or an AI assistant through the connector.
  attribute :editor, :string, default: "owner"

  validates :status, inclusion: { in: STATUSES.keys }
  validates :body, length: { maximum: 25_000 }
  validates :topic, length: { maximum: 120 }
  validates :inspiration_url, format: { with: %r{\Ahttps://(?:www\.)?(?:x|twitter)\.com/\S+\z} }, allow_blank: true
  validates :source, :editor, inclusion: { in: SOURCES }
  validate { errors.add(:base, "Write something, or add a topic or note") if body.blank? && topic.blank? && notes.blank? }

  before_save { self.source = editor if will_save_change_to_body? }
  after_save :record_revision, if: -> { saved_change_to_body? && body.present? }
  # The editor names one change; later saves on the same object are the owner's unless set again.
  after_save { self.editor = "owner"; clear_attribute_changes([:editor]) }

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
    owner = Current.workspace.owner_x_id
    return if owner.blank?
    where(status: %w[ready posted], posted_x_id: nil).find_each do |draft|
      key = draft.match_key
      next if key.size < 20
      post = X::SourcePost.where(author_x_id: owner, repost: false).where.not(x_id: where.not(posted_x_id: nil).select(:posted_x_id))
        .order(published_at: :desc).find { |candidate| normalize(candidate.body).start_with?(key) }
      draft.update!(status: "posted", posted_x_id: post.x_id, posted_at: post.published_at) if post
    end
  end

  def self.normalize(text)
    CGI.unescapeHTML(text.to_s).gsub(URL, "").squish.downcase
  end

  # Saves an idea with its versions: the first text becomes the main draft, the rest alternatives.
  def self.capture!(texts:, editor: "owner", note: nil, **attributes)
    texts = Array(texts).map { |text| text.to_s.strip }.reject(&:blank?)
    transaction do
      draft = create!(attributes.merge(body: texts.first.to_s, editor: editor))
      draft.add_alternatives!(texts.drop(1), source: editor, note: note)
      draft
    end
  end

  def add_alternatives!(texts, source: "owner", note: nil)
    texts = Array(texts).map { |text| text.to_s.strip }.reject(&:blank?)
    if alternatives.count + texts.size > MAX_ALTERNATIVES
      errors.add(:base, "A draft keeps at most #{MAX_ALTERNATIVES} alternatives")
      raise ActiveRecord::RecordInvalid, self
    end
    transaction { texts.map { |text| alternatives.create!(body: text, source: source, note: note) } }
  end

  # Makes an alternative the main text. The previous main text becomes an alternative, so the swap can be undone.
  def use_alternative!(alternative)
    transaction do
      previous_body, previous_source = body, source
      @new_revision = true
      update!(body: alternative.body, editor: alternative.source)
      if previous_body.present?
        alternative.update!(body: previous_body, source: previous_source, note: "Previous main version")
      else
        alternative.destroy!
      end
    end
  end

  # Brings back an earlier main text as a new step in the history.
  def restore!(revision)
    @new_revision = true
    update!(body: revision.body, editor: "owner")
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

  def posted_url
    "https://x.com/i/status/#{posted_x_id}" if posted_x_id
  end

  def next_status
    STATUSES.keys[STATUSES.keys.index(status) + 1]
  end

  private

  def record_revision
    latest = revisions.newest_first.first
    if latest && !@new_revision && latest.source == editor && latest.updated_at > Draft::Revision::COALESCE_WITHIN.ago
      latest.update!(body: body)
    else
      revisions.create!(body: body, source: editor)
    end
    @new_revision = false
  end
end
