# Prompts for what to post next, built only from saved data. No X reads, no AI calls.
class Draft::Ideas
  def initialize(workspace = Workspace.current)
    @workspace = workspace
    @owner = workspace.owner_x_id
  end

  def interests
    @workspace.interests
  end

  def own_posts
    @own_posts ||= owned.where(parent_x_id: nil).order(published_at: :desc).limit(12).to_a
  end

  # Your longer replies in conversations that became two-way: material that already worked in a thread.
  def replies_to_expand
    two_way = ReplyEvent.where(direction: "incoming").select(:person_id)
    ids = ReplyEvent.where(direction: "outgoing", person_id: two_way).order(occurred_at: :desc).limit(200).pluck(:x_id)
    owned.where(x_id: ids).order(published_at: :desc).to_a
      .select { |post| strip_mentions(post.body).size >= 90 }
      .reject { |post| drafted?(post) }
      .first(8)
  end

  # Questions people asked in replies to you.
  def questions
    ids = ReplyEvent.where(direction: "incoming").order(occurred_at: :desc).limit(300).pluck(:x_id)
    XSourcePost.where(x_id: ids).order(published_at: :desc).to_a
      .select { |post| strip_mentions(post.body).include?("?") }
      .reject { |post| drafted?(post) }
      .first(8)
  end

  def authors
    @authors ||= Person.where(x_id: questions.map(&:author_x_id)).index_by(&:x_id)
  end

  def strip_mentions(text)
    CGI.unescapeHTML(text.to_s).sub(/\A(?:@\w+\s+)+/, "").strip
  end

  def status_url(post)
    "https://x.com/i/status/#{post.x_id}"
  end

  def grok_prompt
    recent = own_posts.first(8).map { |post| "- #{strip_mentions(post.body).squish.truncate(200)}" }
    drafts = Draft.where.not(status: "posted").recent.limit(10).filter_map(&:title).map { |title| "- #{title.truncate(120)}" }
    <<~PROMPT
      Suggest 10 X posts I could write this week. I'm a builder who posts in English.

      My focus areas:
      #{interests.map { |interest| "- #{interest}" }.join("\n")}

      What I posted recently (avoid repeating these):
      #{recent.presence&.join("\n") || "- Nothing collected yet"}

      Ideas I'm already drafting:
      #{drafts.presence&.join("\n") || "- None yet"}

      For each suggestion give: a one-line angle, why people in these areas would care right now, and a link to a recent public post or discussion that shows the interest. Prefer concrete experiences, lessons, numbers, and questions over hot takes. Don't write the post for me.
    PROMPT
  end

  private

  def owned
    @owner.present? ? XSourcePost.where(author_x_id: @owner, repost: false) : XSourcePost.none
  end

  def drafted?(post)
    @drafted ||= Draft.where.not(inspiration_url: nil).pluck(:inspiration_url).to_set
    @drafted.include?(status_url(post))
  end
end
