class Session < ApplicationRecord
  # Long on purpose: each X sign-in costs a paid identity read, and Cloudflare Access already guards the edge.
  LIFETIME = 1.year
  belongs_to :user

  scope :active, -> { where(created_at: LIFETIME.ago..) }
end
