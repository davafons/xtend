# The people the owner tends. Three tiers form a ladder, Getting to know → Circle → Inner circle, and a person sits on
# at most one rung; custom lists ("Tokyo devs", "Rails") group people any way the owner likes and overlap freely.
#
# A cadence says how often the owner means to reply to each member. Members past it are due (see Network::Tend).
# Capacity is a soft limit: Xtend shows when a tier is over it but never refuses a member.
class List < ApplicationRecord
  include WorkspaceScoped
  TIERS = {
    "inner" => { name: "Inner circle", cadence_days: 3, capacity: 10, position: 0,
      purpose: "The ten people you most want to be seen by. Turn on X notifications for them and reply early." },
    "circle" => { name: "Circle", cadence_days: 7, capacity: 50, position: 1,
      purpose: "Active accounts in your niche you reply to every week, so they keep seeing you." },
    "getting_to_know" => { name: "Getting to know", cadence_days: 14, capacity: nil, position: 2,
      purpose: "People you've started talking with. Two-way exchanges here are a sign to move them up." }
  }.freeze
  LADDER = %w[getting_to_know circle inner].freeze
  CIRCLE_TIERS = %w[inner circle].freeze
  NAME_LENGTH = 40

  has_many :memberships, class_name: "ListMembership", dependent: :destroy
  has_many :people, through: :memberships

  validates :name, presence: true, length: { maximum: NAME_LENGTH }, uniqueness: { scope: :workspace_id, case_sensitive: false }
  validates :tier, inclusion: { in: TIERS.keys }, allow_nil: true
  validates :cadence_days, numericality: { only_integer: true, in: 1..365 }, allow_nil: true
  validates :capacity, numericality: { only_integer: true, in: 1..1000 }, allow_nil: true
  before_validation { self.name = name.to_s.squish }

  scope :tiers, -> { where.not(tier: nil).order(:position) }
  scope :custom, -> { where(tier: nil).order(Arel.sql("name COLLATE NOCASE")) }
  scope :ordered, -> { order(Arel.sql("tier IS NULL, position, name COLLATE NOCASE")) }

  # Every workspace has the three tiers; they are created the first time anything asks for them.
  def self.ensure_tiers!
    existing = unscope(:order).where.not(tier: nil).pluck(:tier)
    (TIERS.keys - existing).each do |key|
      create!(TIERS.fetch(key).merge(tier: key))
    rescue ActiveRecord::RecordNotUnique
      nil
    end
    nil
  end

  def self.tier(key)
    ensure_tiers!
    find_by!(tier: key)
  end

  # People in the Circle or Inner circle tiers: who the growth plan means by "your circle".
  def self.circle_people
    ensure_tiers!
    Person.where(id: ListMembership.joins(:list).where(lists: { tier: CIRCLE_TIERS }).select(:person_id))
  end

  # Finds a list by id, tier key, or name, case-insensitively.
  def self.lookup(ref)
    ensure_tiers!
    value = ref.to_s.strip
    return find_by(id: value) if value.match?(/\A\d+\z/)
    find_by(tier: value.parameterize(separator: "_")) || where("name = ? COLLATE NOCASE", value.squish).first
  end

  def tier? = tier.present?
  def over_capacity? = capacity && members_count > capacity
  def members_count = memberships.size

  # The tier above this one on the ladder, if any.
  def next_tier
    return unless tier?
    key = LADDER[LADDER.index(tier) + 1]
    List.tier(key) if key
  end

  # Adds a person. On a tier, the person leaves whatever tier they were on: moving up or down the ladder.
  # An AI may only place someone who isn't on a tier yet, so it never moves the owner's choices.
  # Returns the membership, or nil when nothing changed.
  def add!(person, source: "owner")
    transaction do
      return if memberships.exists?(person: person)
      if tier?
        others = ListMembership.joins(:list).where(person: person).where.not(lists: { tier: nil })
        return if source == "ai" && others.exists?
        others.destroy_all
      end
      memberships.create!(person: person, source: source)
    end
  end

  def remove!(person)
    memberships.where(person: person).destroy_all.any?
  end
end
