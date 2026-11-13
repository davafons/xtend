# The owner's labels for people, such as "tokyo" or "ios dev". Tags are the owner's data: X sync never
# changes them, and AI can only propose them.
class Tag < ApplicationRecord
  include WorkspaceScoped
  MAX_LENGTH = 40
  has_many :person_tags, dependent: :destroy
  has_many :people, through: :person_tags

  before_validation { self.name = self.class.normalize(name) }
  validates :name, presence: true, length: { maximum: MAX_LENGTH }, uniqueness: { scope: :workspace_id }

  scope :by_use, -> { left_joins(:person_tags).group(:id).select("tags.*, COUNT(person_tags.id) AS people_count").order(Arel.sql("COUNT(person_tags.id) DESC"), :name) }

  def self.normalize(value)
    value.to_s.unicode_normalize(:nfkc).delete_prefix("#").squish.downcase.first(MAX_LENGTH)
  end

  # Splits "tokyo, ios dev" into tag names.
  def self.names_from(value)
    Array.wrap(value).flat_map { |item| item.to_s.split(",") }.map { |name| normalize(name) }.reject(&:blank?).uniq
  end

  def self.named(name)
    find_or_create_by!(name: normalize(name))
  rescue ActiveRecord::RecordNotUnique
    find_by!(name: normalize(name))
  end
end
