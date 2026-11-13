# What the ⌘K search finds across the owner's saved data. A blank query finds nothing; the palette then
# shows its commands and the people you talked to last.
class Search
  LIMIT = 6
  POST_LIMIT = 3

  attr_reader :query

  def initialize(query)
    @query = query.to_s.strip.first(100)
  end

  def blank?
    query.empty?
  end

  def people
    return Person.none if blank?

    @people ||= Person.where("name LIKE :q OR handle LIKE :q OR description LIKE :q OR notes LIKE :q", q: pattern(handle_term))
      .order(Arel.sql("CASE WHEN handle LIKE #{Person.connection.quote(prefix(handle_term))} OR name LIKE #{Person.connection.quote(prefix(handle_term))} THEN 0 ELSE 1 END"),
        Arel.sql("EXISTS (SELECT 1 FROM reply_events WHERE reply_events.person_id = people.id) DESC"), followers_count: :desc)
      .includes(:pin, :follow_protection, :tags).limit(LIMIT).to_a
  end

  # The person the query names outright, by handle or full name, for the palette's quick actions.
  def named_person
    return if blank?
    wanted = handle_term.downcase
    people.find { |person| person.handle.downcase == wanted || person.name.downcase == wanted }
  end

  # Where the query matched a person, when it wasn't their name or handle: their bio or your notes.
  def match_in(person)
    term = handle_term.downcase
    return if [ person.name, person.handle ].any? { |field| field.to_s.downcase.include?(term) }
    [ [ "Notes", person.notes ], [ "Bio", person.description ] ].find { |_, text| text.to_s.downcase.include?(term) }
  end

  def tags
    blank? ? [] : (@tags ||= Tag.by_use.where("name LIKE ?", pattern).limit(LIMIT).to_a)
  end

  # A few of the best-known people with the tag, for the tag row's avatars.
  def tagged_people(tag)
    tag.people.order(followers_count: :desc).limit(3)
  end

  def drafts
    blank? ? [] : (@drafts ||= Draft.where("body LIKE :q OR topic LIKE :q OR notes LIKE :q", q: pattern).order(updated_at: :desc).limit(LIMIT).to_a)
  end

  def post_count
    blank? ? 0 : (@post_count ||= matching_posts.count)
  end

  # The newest saved posts that match, previewed in the palette.
  def posts
    blank? ? [] : (@posts ||= matching_posts.order(published_at: :desc).limit(POST_LIMIT).to_a)
  end

  # Authors of the previewed posts: people first, then accounts the capture has seen.
  def post_authors
    @post_authors ||= begin
      ids = posts.map(&:author_x_id).uniq
      people = Person.where(x_id: ids).index_by(&:x_id)
      X::Account.where(x_id: ids - people.keys).index_by(&:x_id).merge(people)
    end
  end

  # Most recent conversations, for the palette before anything is typed.
  def recent_people
    @recent_people ||= Person.where(id: ReplyEvent.group(:person_id).order(Arel.sql("MAX(occurred_at) DESC")).limit(LIMIT).select(:person_id))
      .includes(:pin, :follow_protection, :reply_events).sort_by { |person| -person.last_interaction_at.to_f }
  end

  def follow_graph
    @follow_graph ||= Follow::Graph.latest
  end

  private

  def matching_posts
    X::SourcePost.where(repost: false).where("body LIKE ?", pattern)
  end

  # "@ada" finds the handle "ada"; a lone "@" stays as typed.
  def handle_term
    query.delete_prefix("@").presence || query
  end

  def pattern(term = query)
    "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
  end

  def prefix(term = query)
    "#{ActiveRecord::Base.sanitize_sql_like(term)}%"
  end
end
