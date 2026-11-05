class Pin < ApplicationRecord
  belongs_to :person
  validates :person_id, uniqueness: true
end
