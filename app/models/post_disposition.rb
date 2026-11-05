class PostDisposition < ApplicationRecord
  belongs_to :post
  validates :post_id, uniqueness: true
  validates :kind, inclusion: { in: %w[skipped snoozed] }
end
