class ReplyReport < ApplicationRecord
  belongs_to :post
  validates :post_id, uniqueness: true
  validates :reply_url, format: { with: %r{\Ahttps://(?:www\.)?(?:x\.com|twitter\.com)/[A-Za-z0-9_]+/status/\d+\z} }, allow_blank: true
end
