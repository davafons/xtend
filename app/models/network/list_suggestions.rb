# Who to move on the ladder, from observed replies. Up: people on no tier who replied back and forth recently go to
# Getting to know; people there who keep replying go to Circle. Fading: Circle and Inner circle members you haven't
# replied to in twice their cadence. Suggestions only; the owner moves people.
class Network::ListSuggestions
  WINDOW = 60.days
  CIRCLE_REPLIES = 2
  LIMIT = 8

  Suggestion = Data.define(:person, :kind, :list, :reason)

  def initialize(now: Time.current)
    @now = now
  end

  def promote
    @promote ||= to_getting_to_know + to_circle
  end

  def fading
    @fading ||= begin
      memberships = ListMembership.joins(:list).where(lists: { tier: List::CIRCLE_TIERS }).includes(:list, :person)
      last = ReplyEvent.where(direction: "outgoing", person_id: memberships.map(&:person_id)).group(:person_id).maximum(:occurred_at)
      memberships.filter_map do |membership|
        limit = membership.list.cadence_days * 2
        since = last[membership.person_id] || membership.created_at
        next if since > @now - limit.days
        days = ((@now - since) / 1.day).floor
        reason = last[membership.person_id] ? "No reply from you in #{days} days" : "Never replied since you added them #{days} days ago"
        Suggestion.new(membership.person, :fading, membership.list, reason)
      end.sort_by { [ _1.list.position, _1.reason ] }.first(LIMIT)
    end
  end

  private

  def recent = ReplyEvent.where(occurred_at: (@now - WINDOW)..)

  def to_getting_to_know
    tiered = ListMembership.joins(:list).where.not(lists: { tier: nil }).select(:person_id)
    counts = recent.where.not(person_id: tiered).group(:person_id, :direction).count
    ids = counts.keys.map(&:first).uniq.select { |id| counts[[ id, "outgoing" ]].to_i.positive? && counts[[ id, "incoming" ]].to_i.positive? }
    list = List.tier("getting_to_know")
    Person.where(id: ids).to_a.map do |person|
      Suggestion.new(person, :promote, list, "Two-way: #{counts[[ person.id, 'outgoing' ]]} from you, #{counts[[ person.id, 'incoming' ]]} from them in #{WINDOW.in_days.to_i} days")
    end.sort_by { -(counts[[ _1.person.id, "incoming" ]]) }.first(LIMIT)
  end

  def to_circle
    members = Person.in_list(List.tier("getting_to_know")).select(:id)
    counts = recent.where(person_id: members, direction: "incoming").group(:person_id).count.select { _2 >= CIRCLE_REPLIES }
    list = List.tier("circle")
    Person.where(id: counts.keys).to_a.map do |person|
      Suggestion.new(person, :promote, list, "Replied to you #{counts[person.id]} times in #{WINDOW.in_days.to_i} days")
    end.sort_by { -counts[_1.person.id] }.first(LIMIT)
  end
end
