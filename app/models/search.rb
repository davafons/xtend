# What the ⌘K search finds across the owner's saved data. A blank query finds nothing; the palette then
# shows its commands and the people you talked to last.
class Search
  LIMIT = 6

  attr_reader :query

  def initialize(query)
    @query = query.to_s.strip.first(100)
  end

  def blank?
    query.empty?
  end

  def people
    return Person.none if blank?

    @people ||= Person.where("name LIKE :q OR handle LIKE :q OR description LIKE :q OR notes LIKE :q", q: pattern)
      .order(Arel.sql("CASE WHEN handle LIKE #{Person.connection.quote(prefix)} OR name LIKE #{Person.connection.quote(prefix)} THEN 0 ELSE 1 END"), followers_count: :desc)
      .limit(LIMIT).to_a
  end

  def tags
    blank? ? [] : (@tags ||= Tag.where("name LIKE ?", pattern).order(:name).limit(LIMIT).to_a)
  end

  def drafts
    blank? ? [] : (@drafts ||= Draft.where("body LIKE :q OR topic LIKE :q OR notes LIKE :q", q: pattern).order(updated_at: :desc).limit(LIMIT).to_a)
  end

  def post_count
    blank? ? 0 : (@post_count ||= X::SourcePost.where(repost: false).where("body LIKE ?", pattern).count)
  end

  # Most recent conversations, for the palette before anything is typed.
  def recent_people
    @recent_people ||= Person.where(id: ReplyEvent.group(:person_id).order(Arel.sql("MAX(occurred_at) DESC")).limit(LIMIT).select(:person_id))
      .sort_by { |person| -person.reply_events.maximum(:occurred_at).to_f }
  end

  private

  def pattern
    "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
  end

  def prefix
    "#{ActiveRecord::Base.sanitize_sql_like(query)}%"
  end
end
