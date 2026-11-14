# Where each relationship stands, as columns from strangers to your circle. The first three stages come from
# observed replies for people on no tier; the last two are the tiers you placed people on. Missing reply history is
# not proof of none, so "Noticed" only means Xtend saw no replies.
class Network::Pipeline
  LIMIT = 30
  NOTICED_WINDOW = 14.days
  STAGES = {
    "noticed" => [ "Noticed", "Recent reply candidates with no replies seen either way." ],
    "replied" => [ "You replied", "You replied; no reply back seen yet." ],
    "two_way" => [ "Two-way", "Replies seen both ways. Ready for Getting to know." ],
    "getting_to_know" => [ "Getting to know", "On your Getting to know tier." ],
    "circle" => [ "Circle", "Your Circle and Inner circle." ]
  }.freeze

  Column = Data.define(:key, :label, :description, :people, :total, :next_list)

  def initialize(now: Time.current)
    @now = now
  end

  def columns
    List.ensure_tiers!
    STAGES.map do |key, (label, description)|
      scope = scope_for(key)
      Column.new(key, label, description, ordered(key, scope).limit(LIMIT).to_a, scope.count, next_list(key))
    end
  end

  private

  def scope_for(key)
    tiered = ListMembership.joins(:list).where.not(lists: { tier: nil }).select(:person_id)
    outgoing = ReplyEvent.where(direction: "outgoing").select(:person_id)
    incoming = ReplyEvent.where(direction: "incoming").select(:person_id)
    loose = Person.where.not(id: tiered)
    case key
    when "noticed"
      loose.where.not(id: ReplyEvent.select(:person_id)).where(id: Outreach::Candidate.where(published_at: (@now - NOTICED_WINDOW)..).select(:person_id))
    when "replied" then loose.where(id: outgoing).where.not(id: incoming)
    when "two_way" then loose.where(id: outgoing).where(id: incoming)
    when "getting_to_know" then Person.in_list(List.tier("getting_to_know"))
    when "circle" then List.circle_people
    end
  end

  def ordered(key, scope)
    people = scope.includes(:pin, :lists, :reply_events)
    if key == "noticed"
      people.order(Arel.sql("(SELECT MAX(published_at) FROM outreach_candidates WHERE outreach_candidates.person_id = people.id) DESC"))
    else
      people.order(Arel.sql("(SELECT MAX(occurred_at) FROM reply_events WHERE reply_events.person_id = people.id) IS NULL, " \
        "(SELECT MAX(occurred_at) FROM reply_events WHERE reply_events.person_id = people.id) DESC, people.name COLLATE NOCASE"))
    end
  end

  # Where "move up" takes someone from this column.
  def next_list(key)
    case key
    when "noticed", "replied", "two_way" then List.tier("getting_to_know")
    when "getting_to_know" then List.tier("circle")
    when "circle" then List.tier("inner")
    end
  end
end
