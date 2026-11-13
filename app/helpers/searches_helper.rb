# Rows for the ⌘K palette that carry more than an icon: who someone is, what a tag holds, where a draft stands.
module SearchesHelper
  # Matches the library's icon badges, so avatar rows and icon rows line up.
  SEARCH_AVATAR = "shrink-0 [--lc-avatar-size:--spacing(10)]"

  def person_search_result(person, graph:, detail: nil)
    state = person.follow_state(graph)
    marks = safe_join([
      (lc_icon("bookmark", variant: :solid, options: { class: "size-3.5 shrink-0 text-you", "aria-label": "Pinned" }) if person.pin),
      (lc_icon("shield-check", variant: :solid, options: { class: "size-3.5 shrink-0 text-success", "aria-label": "Kept" }) if person.follow_protection)
    ].compact)
    facts = [
      "@#{person.handle}",
      (tag.span(class: ApplicationHelper::MEANING_TEXT.fetch(state_meaning(state))) { safe_join([ lc_icon(relationship_icon(state), options: { class: "inline size-3.5 align-text-bottom", "aria-hidden": true }), " ", state ]) } if state_meaning(state) != :neutral),
      ("#{compact_count(person.followers_count)} followers" if person.followers_count),
      detail
    ].compact
    tags = person.tags.first(3).map { |label| lc_badge("##{label.name}", shape: :pill, class: tag_hue(label.name)) }
    search_row(person.name, person_path(person), leading: person_avatar(person, ring: state, class: SEARCH_AVATAR), marks: marks,
      detail: safe_join(facts, " · "), extra: (tag.span(safe_join(tags), class: "flex flex-wrap gap-tight") if tags.any?))
  end

  def tag_search_result(label, people)
    count = label.people_count.to_i
    stack = lc_avatar_stack(compact: true) { safe_join(people.map { |person| person_avatar(person, size: :xs) }) } if people.any?
    search_row("##{label.name}", people_path(tag: label.name), leading: lc_icon_badge("#", class: tag_hue(label.name)),
      detail: tag.span(class: "inline-flex items-center gap-related") { safe_join([ stack, pluralize(count, "person", plural: "people") ].compact) })
  end

  def draft_search_result(draft)
    title = draft.title.to_s.squish.truncate(70).presence || "Untitled draft"
    detail = safe_join([
      lc_badge(Draft::STATUSES.fetch(draft.status).singularize),
      (ai_badge if draft.source == "ai"),
      tag.span("edited #{time_ago_in_words(draft.updated_at)} ago")
    ].compact, " ")
    search_row(title, edit_draft_path(draft), leading: lc_icon_badge(icon: draft.source == "ai" ? "sparkles" : "pencil-square", class: (ApplicationHelper::MEANING_CLASSES[:ai] if draft.source == "ai")),
      detail: detail)
  end

  def post_search_result(post, author)
    owner = post.author_x_id == Current.workspace.owner_x_id
    name = owner ? "You" : author&.name || "Unknown account"
    avatar =
      if owner then owner_avatar
      elsif author.is_a?(Person) then person_avatar(author)
      elsif author&.avatar_url && !demo? then lc_avatar(src: author.avatar_image_url, alt: "", referrerpolicy: "no-referrer", loading: "lazy")
      else lc_avatar(name.first(2).upcase)
      end
    title = safe_join([ name, (tag.span("@#{author.handle}", class: "font-normal text-muted-foreground") if author && !owner), tag.span("· #{time_ago_in_words(post.published_at)} ago", class: "font-normal text-muted-foreground") ].compact, " ")
    search_row(title, "https://x.com/i/status/#{post.x_id}", leading: tag.span(avatar, class: SEARCH_AVATAR),
      detail: CGI.unescapeHTML(post.body).squish.truncate(160), target: "_blank", rel: "noopener noreferrer")
  end

  private

  # The library row with our own leading visual in place of its icon badge.
  def search_row(title, url, leading:, detail:, marks: nil, extra: nil, **attributes)
    lc_search_result(title.to_s, url, **attributes) do
      safe_join([
        leading,
        tag.span(class: "flex min-w-0 flex-1 flex-col gap-tight") do
          safe_join([
            tag.span(class: "flex min-w-0 items-center gap-tight text-label font-semibold", data: { slot: "search-result-title" }) { safe_join([ tag.span(title, class: "truncate"), marks ].compact) },
            tag.span(detail, class: Lostcoords::Ui::SearchHelper::RESULT_DETAIL, data: { slot: "search-result-detail" }),
            extra
          ].compact)
        end
      ])
    end
  end
end
