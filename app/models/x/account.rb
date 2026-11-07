# Every X account the browser capture has seen, whether or not it is a person in the CRM. People stay the owner's
# curated records; accounts are the directory behind the network view.
class X::Account < ApplicationRecord
  include WorkspaceScoped
  self.table_name = "x_accounts"

  has_one :person, primary_key: :x_id, foreign_key: :x_id, inverse_of: false

  def self.observe!(rows, at: Time.current)
    rows.each do |row|
      account = find_or_initialize_by(x_id: row.fetch("id"))
      account.assign_attributes(handle: row.fetch("username").downcase, name: row.fetch("name").presence || row.fetch("username"),
        description: row["description"], avatar_url: row["profile_image_url"], verified: row["verified"] == true,
        followers_count: row["followers_count"], following_count: row["following_count"], posts_count: row["posts_count"],
        observed_at: at)
      account.save!
    end
  end

  def avatar_image_url
    avatar_url&.sub(/_normal(\.\w+)\z/, "_bigger\\1")
  end

  def profile_url
    "https://x.com/#{handle}"
  end
end
