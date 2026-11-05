class Pin < ApplicationRecord
  include WorkspaceScoped
  belongs_to :person
  validates :person_id, uniqueness: true
end
