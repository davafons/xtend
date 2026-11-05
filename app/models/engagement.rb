class Engagement < ApplicationRecord
  KINDS = { "liked_posts" => "like", "bookmarks" => "bookmark" }.freeze

  belongs_to :x_sync_run, class_name: "X::SyncRun"
  validates :kind, inclusion: { in: KINDS.values }
  validates :post_x_id, uniqueness: { scope: :kind }
  validates :post_x_id, :author_x_id, :post_published_at, :observed_at, presence: true

  # Returns :new, :known, or :skipped so a refresh can stop once it reaches earlier evidence.
  def self.capture!(row, kind:, run:, observed_after: nil)
    return :skipped if row.fetch("author_id") == Workspace.current.owner_x_id
    record = find_or_initialize_by(kind: kind, post_x_id: row.fetch("id"))
    return :known if record.persisted?
    record.update!(author_x_id: row.fetch("author_id"), body: row.fetch("text"),
      post_published_at: Time.iso8601(row.fetch("created_at")), observed_after: observed_after,
      observed_at: Time.current, x_sync_run: run)
    :new
  end

  def self.coverage(kind)
    dataset = KINDS.key(kind)
    runs = X::SyncRun.where(dataset: dataset, status: "completed")
    { complete: runs.where(mode: "backfill").exists?, checked_at: runs.maximum(:upper_bound), collected: where(kind: kind).exists? }
  end

  # X reports when the post was published, not when you liked or bookmarked it.
  # A refresh narrows that to "after the previous complete check".
  def earliest_at
    [post_published_at, observed_after].compact.max
  end
end
