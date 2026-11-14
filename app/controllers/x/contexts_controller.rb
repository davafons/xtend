# What Xtend knows about the people x.com is showing, for the extension to place beside their names: where you stand,
# replies both ways, the last interaction and the last reply exchanged, and your own pins, tags, notes, and reminder,
# plus whether now is a busy hour for your audience and how fresh your X analytics are. Read-only, with the same
# extension link that sends captures. A handle Xtend has no person for comes back as unknown, and as following neither way only when both follow lists are
# complete.
class X::ContextsController < ActionController::API
  MAX_HANDLES = 100
  # The tab of the person's history in Xtend that lists each kind of interaction.
  HISTORY = { "like" => "engagement", "bookmark" => "engagement", "dm" => "messages", "reply" => "conversation" }.freeze
  rate_limit to: 120, within: 1.minute, store: RATE_LIMIT_STORE, by: -> { request.remote_ip },
    with: -> { render json: { error: "Too many requests. Slow down." }, status: :too_many_requests }
  include ExtensionAuthentication

  def show
    handles = params[:handles].to_s.split(",").map { |handle| handle.strip.delete_prefix("@").downcase }
      .grep(/\A\w{1,15}\z/).uniq.first(MAX_HANDLES)
    people = Person.where("lower(handle) IN (?)", handles).includes(:pin, :follow_protection, :tags, :reply_events, :reminders).to_a
    graph = Follow::Graph.latest
    interactions = Person::Interactions.index(people)
    exchanges = last_exchanges(people)
    known = people.to_h { |person| [ person.handle.downcase, summary(person, graph, interactions.fetch(person.id)).merge(last_exchange: exchanges[person.id]) ] }
    # Everyone in your complete follow lists is a person, so a handle without one follows neither way as of the older
    # check. Partial lists can't establish that.
    stranger = graph.complete? ? { known: false, follow: "Neither", meaning: "neutral" } : { known: false }
    render json: { follow_data: graph.complete? ? "complete" : "partial",
      follow_checked_at: (graph.complete? ? [ graph.following.completed_at, graph.followers.completed_at ].min.iso8601 : nil),
      people: handles.to_h { |handle| [ handle, known[handle] || stranger ] }, you: account }
  end

  private

  # Your audience's usual activity now (from the X analytics heatmap) and when X analytics were last collected.
  def account
    hours = Network::ActiveHours.new
    level = hours.level
    seen = X::Analytics.last_collected_at
    { timing: level && { level: level, next_busy_at: (hours.next_busy&.iso8601 unless level == :busy), time_zone: Time.zone.tzinfo.name },
      analytics: { last_seen_at: seen&.iso8601, stale: X::Analytics.stale?(seen), url: X::Analytics::URL } }
  end

  # The newest reply between you and each person, either way, with its text when the post was saved: { person_id => {...} }.
  def last_exchanges(people)
    latest = people.filter_map { |person| person.reply_events.max_by(&:occurred_at) }
    bodies = X::SourcePost.where(x_id: latest.map(&:x_id)).pluck(:x_id, :body).to_h
    latest.to_h do |event|
      [ event.person_id, { direction: event.direction, at: event.occurred_at.iso8601, url: "https://x.com/i/status/#{event.x_id}",
        text: bodies[event.x_id] && CGI.unescapeHTML(bodies[event.x_id]).sub(/\A(@\w+\s+)+/, "").squish.truncate(200) } ]
    end
  end

  def summary(person, graph, interactions)
    state = person.follow_state(graph)
    reminder = person.reminders.select { |item| item.completed_at.nil? }.min_by(&:due_on)
    latest = interactions.latest
    {
      known: true, name: person.name, handle: person.handle, url: person_url(person),
      follow: state, meaning: ApplicationController.helpers.state_meaning(state),
      replies: { from_you: person.outgoing_count, from_them: person.incoming_count },
      last_reply_at: person.last_interaction_at&.iso8601,
      latest: latest && { label: ApplicationController.helpers.interaction_label(latest), at: latest.at.iso8601, channel: latest.channel,
        direction: latest.direction, url: person_url(person, show: HISTORY[latest.channel]) },
      pinned: person.pin.present?, kept: person.follow_protection.present?,
      tags: person.tags.map { |tag| { name: tag.name, hue: ApplicationController.helpers.tag_hue(tag.name)[/bg-(\w+)-/, 1], url: people_url(tag: tag.name) } },
      notes: person.notes.presence,
      reminder: reminder && { reason: reminder.reason, due_on: reminder.due_on.iso8601, due: reminder.due? }
    }
  end
end
