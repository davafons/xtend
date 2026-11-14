class Workspace < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :oauth_grants, class_name: "Oauth::Grant", dependent: :destroy
  has_many :oauth_authorization_codes, class_name: "Oauth::AuthorizationCode", dependent: :delete_all
  validates :name, presence: true
  validates :monthly_budget_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100_000 }

  def interests
    builder_interests.lines.map(&:strip).reject(&:blank?)
  end
end
