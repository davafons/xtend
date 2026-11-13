# An X account allowed to sign in. There is no signup: `bin/rails users:allow HANDLE=...` adds one.
# The first sign-in pins the account's X user ID, so a later handle change keeps access and
# someone who takes over the old handle doesn't get it.
class User < ApplicationRecord
  belongs_to :workspace
  has_many :sessions, dependent: :destroy
  has_many :oauth_grants, class_name: "Oauth::Grant", dependent: :nullify
  has_many :oauth_authorization_codes, class_name: "Oauth::AuthorizationCode", dependent: :delete_all
  # Dim: X's blue-grey.
  THEMES = %w[dim].freeze

  validates :theme, inclusion: { in: THEMES }

  normalizes :x_handle, with: ->(handle) { handle.strip.delete_prefix("@").downcase }
  validates :x_handle, presence: true, uniqueness: true, format: { with: /\A\w{1,15}\z/ }
  validates :x_user_id, uniqueness: true, allow_nil: true

  # Returns the allowed user for this X identity, pinning its ID on first sign-in, or nil.
  def self.for_x_identity(identity)
    id, handle = identity.fetch("id"), identity.fetch("username")
    if user = find_by(x_user_id: id)
      user.update!(x_handle: handle) unless user.x_handle == handle.downcase || exists?(x_handle: handle.downcase)
      user
    elsif user = find_by(x_handle: handle, x_user_id: nil)
      user.update!(x_user_id: id)
      user
    end
  end
end
