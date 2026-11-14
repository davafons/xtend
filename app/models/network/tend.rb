# Who in your lists you mean to reply to and haven't lately. Each member of a list with a cadence is due once that
# many days have passed since your last confirmed reply to them, or when you've never replied. A person on several
# lists follows the shortest cadence. Their newest post from the last two days you haven't answered comes along,
# so the reply can start right there.
class Network::Tend
  Item = Data.define(:person, :lists, :cadence_days, :last_reply_at, :fresh_post, :now) do
    def days_since = last_reply_at && ((now - last_reply_at) / 1.day).floor
    def due? = last_reply_at.nil? || days_since >= cadence_days
    def due_in = due? ? 0 : cadence_days - days_since
    def tier_rank = lists.filter_map { List::LADDER.reverse.index(_1.tier) if _1.tier? }.min || List::LADDER.size
  end

  def initialize(list: nil, now: Time.current)
    @list = list
    @now = now
  end

  def items
    @items ||= begin
      memberships = ListMembership.joins(:list).where.not(lists: { cadence_days: nil }).includes(:list, person: [ :pin, :tags, :lists ])
      memberships = memberships.where(list: @list) if @list
      by_person = memberships.group_by(&:person)
      people = by_person.keys
      last = ReplyEvent.where(direction: "outgoing", person_id: people.map(&:id)).group(:person_id).maximum(:occurred_at)
      fresh = X::SourcePost.fresh_unanswered(people.map(&:x_id))
      by_person.map do |person, rows|
        lists = rows.map(&:list)
        Item.new(person, lists, lists.map(&:cadence_days).min, last[person.id], (fresh[person.x_id] if person.x_id), @now)
      end
    end
  end

  # Due people, those with a fresh post first, then the inner circle before the rest, then the longest waiting.
  def due
    items.select(&:due?).sort_by { [ _1.fresh_post ? 0 : 1, _1.tier_rank, -(_1.days_since || 10_000), _1.person.name.downcase ] }
  end

  # Members not due yet, soonest first.
  def upcoming
    items.reject(&:due?).sort_by { [ _1.due_in, _1.person.name.downcase ] }
  end
end
