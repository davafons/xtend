# What Xtend knows about the people x.com is showing, for the extension to place beside their names: where you stand,
# replies both ways, the last interaction, and your own pins, tags, notes, and reminder. Read-only, with the same
# extension link that sends captures. A handle Xtend has no person for comes back as unknown, never as "no history".
class X::ContextsController < ActionController::API
  MAX_HANDLES = 100
  rate_limit to: 120, within: 1.minute, store: RATE_LIMIT_STORE, by: -> { request.remote_ip },
    with: -> { render json: { error: "Too many requests. Slow down." }, status: :too_many_requests }
  include ExtensionAuthentication

  def show
    handles = params[:handles].to_s.split(",").map { |handle| handle.strip.delete_prefix("@").downcase }
      .grep(/\A\w{1,15}\z/).uniq.first(MAX_HANDLES)
    people = Person.where("lower(handle) IN (?)", handles).includes(:pin, :follow_protection, :tags, :reply_events, :reminders).to_a
    graph = Follow::Graph.latest
    interactions = Person::Interactions.index(people)
    known = people.to_h { |person| [ person.handle.downcase, summary(person, graph, interactions.fetch(person.id)) ] }
    render json: { follow_data: graph.complete? ? "complete" : "partial",
      people: handles.to_h { |handle| [ handle, known[handle] || { known: false } ] } }
  end

  private

  def summary(person, graph, interactions)
    state = person.follow_state(graph)
    reminder = person.reminders.select { |item| item.completed_at.nil? }.min_by(&:due_on)
    latest = interactions.latest
    {
      known: true, name: person.name, handle: person.handle, url: person_url(person),
      follow: state, meaning: ApplicationController.helpers.state_meaning(state),
      replies: { from_you: person.outgoing_count, from_them: person.incoming_count },
      last_reply_at: person.last_interaction_at&.iso8601,
      latest: latest && { label: ApplicationController.helpers.interaction_label(latest), at: latest.at.iso8601, channel: latest.channel, direction: latest.direction },
      pinned: person.pin.present?, kept: person.follow_protection.present?,
      tags: person.tags.map { |tag| { name: tag.name, hue: ApplicationController.helpers.tag_hue(tag.name)[/bg-(\w+)-/, 1] } },
      notes: person.notes.presence,
      reminder: reminder && { reason: reminder.reason, due_on: reminder.due_on.iso8601, due: reminder.due? }
    }
  end
end
