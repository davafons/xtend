class Post < ApplicationRecord
  belongs_to :person
  has_one :post_disposition, dependent: :destroy
  has_one :reply_report, dependent: :destroy

  validates :x_id, presence: true, uniqueness: true
  validates :x_id, format: { with: /\A\d{1,30}\z/ }
  validates :body, :published_at, presence: true
  validates :language, presence: true

  def self.opportunities
    english = where(language: "en").where("rank >= 0").where("reply_count IS NULL OR reply_count <= 50").where(published_at: 7.days.ago..Time.current)
    hidden = PostDisposition.where(kind: "skipped").or(PostDisposition.where("until_at > ?", Time.current))
    english.where.not(id: hidden.select(:post_id))
      .where.not(x_id: ReplyEvent.where(direction: "outgoing").select(:target_x_id))
      .where.not(x_id: Outreach.select(:target_x_id))
      .where.not(id: ReplyReport.select(:post_id))
      .includes(person: [ :pin, :follow_protection ])
      .left_joins(person: :pin)
      .order(Arel.sql("CASE WHEN pins.id IS NOT NULL THEN 0 ELSE 1 END"), rank: :desc, published_at: :desc)
  end

  def source_url
    "https://x.com/#{person.handle}/status/#{x_id}"
  end
end
