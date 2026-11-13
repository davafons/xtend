# A post worth considering as a reply target: seen by the capture on a discovery surface, or proposed by AI
# and still unverified until X shows it. Rank and reason come from Outreach::Assessment.
class Outreach::Candidate < ApplicationRecord
  include WorkspaceScoped
  belongs_to :person

  validates :x_id, presence: true, uniqueness: { scope: :workspace_id }
  validates :x_id, format: { with: /\A\d{1,30}\z/ }
  validates :body, :published_at, presence: true
  validates :language, presence: true

  def self.opportunities
    where(language: "en").where("rank >= 0").where("reply_count IS NULL OR reply_count <= 50").where(published_at: 7.days.ago..Time.current)
      .where.not(x_id: ReplyEvent.where(direction: "outgoing").select(:target_x_id))
      .where.not(x_id: Outreach::Target.select(:target_x_id))
      .includes(person: [ :pin, :follow_protection ])
      .left_joins(person: :pin)
      .order(Arel.sql("CASE WHEN pins.id IS NOT NULL THEN 0 ELSE 1 END"), rank: :desc, published_at: :desc)
  end

  def source_url
    "https://x.com/#{person.handle}/status/#{x_id}"
  end
end
