class X::SyncRun < ApplicationRecord
  include WorkspaceScoped
  DATASETS = %w[followers following own_posts mentions users posts search liked_posts bookmarks dm_events].freeze
  INTERACTION_DATASETS = %w[liked_posts bookmarks dm_events].freeze
  belongs_to :follow_snapshot, class_name: "Follow::Snapshot", optional: true
  has_many :x_reads, class_name: "X::Read", foreign_key: :x_sync_run_id
  has_many :x_source_posts, class_name: "X::SourcePost", foreign_key: :x_sync_run_id
  validates :dataset, inclusion: { in: DATASETS }
  validates :mode, inclusion: { in: %w[backfill refresh discovery] }
  validates :request_key, presence: true, uniqueness: true
  validates :page_limit, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1000 }

  MAX_PAGE_SIZES = { "followers" => 1000, "following" => 1000, "own_posts" => 100, "mentions" => 100,
    "liked_posts" => 100, "bookmarks" => 100, "dm_events" => 100 }.freeze

  def self.start!(dataset:, request_key:, mode: "backfill", parameters: {}, page_size: nil)
    raise ArgumentError, "Choose a supported source." unless DATASETS.include?(dataset)
    raise X::Client::Error, "Live collection is disabled in demo mode." if Rails.configuration.x.demo
    connection = X::Connection.current || raise(X::Client::Error, "Connect your X account first.")
    raise X::Client::Error, "The connected X account does not match this workspace." unless connection.x_user_id == Current.workspace.owner_x_id
    if (scope = X::Config::DATASET_SCOPES[dataset]) && !connection.granted?(scope)
      raise X::Client::Error, "Reconnect X to grant #{scope}. The current connection was authorized before this source existed."
    end
    existing = find_by(request_key: request_key)
    return existing if existing
    raise ArgumentError, "Invalid collection request." unless request_key.is_a?(String) && request_key.match?(/\A[\w-]{16,100}\z/) && %w[backfill refresh discovery].include?(mode)
    limit = %w[followers following].include?(dataset) ? 100 : 10
    limit = 200 if dataset == "followers" && mode == "refresh"
    limit = { "liked_posts" => 100, "bookmarks" => 100, "dm_events" => 20 }.fetch(dataset, limit)
    if page_size
      maximum = MAX_PAGE_SIZES[dataset] || raise(ArgumentError, "Page size applies only to graph and timeline reads.")
      limit = Integer(page_size).clamp(5, maximum)
    end
    if %w[users posts].include?(dataset)
      ids = parameters.fetch("ids")
      raise ArgumentError, "Choose 1 to 20 numeric X IDs." unless ids.is_a?(Array) && ids.size.between?(1, 20) && ids.all? { |id| id.is_a?(String) && id.match?(/\A\d{1,30}\z/) }
      parameters = { "ids" => ids.uniq, "purpose" => parameters["purpose"] == "discovery" ? "discovery" : "parents" }
      limit = parameters["ids"].size
    elsif dataset == "search"
      query = parameters.fetch("query")
      raise ArgumentError, "Enter a search between 3 and 256 characters." unless query.is_a?(String) && query.size.between?(3, 256)
      parameters = { "query" => "(#{query}) lang:en -is:retweet -from:grok" }
      mode = "discovery"
    else
      parameters = {}
    end
    transaction do
      if INTERACTION_DATASETS.include?(dataset)
        previous = where(dataset: dataset, status: "completed").order(upper_bound: :desc).first
        mode = previous ? "refresh" : "backfill"
        parameters["observed_after"] = previous.upper_bound.utc.iso8601 if previous && dataset != "dm_events"
      end
      if %w[own_posts mentions].include?(dataset) && mode == "refresh"
        last = where(dataset: dataset, mode: "refresh", status: "completed").order(upper_bound: :desc).first
        baseline = last || where(dataset: dataset).order(:upper_bound).first
        if baseline
          parameters["start_time"] = baseline.upper_bound.utc.iso8601
        else
          mode = "backfill"
        end
      end
      run = create!(dataset: dataset, owner_x_id: connection.x_user_id, request_key: request_key,
        mode: mode, page_limit: limit, upper_bound: Time.current.change(usec: 0) - 15.seconds, parameters: parameters)
      if %w[followers following].include?(dataset)
        run.update!(follow_snapshot: Follow::Snapshot.create!(direction: dataset, source: "x_api", observed_at: Time.current))
      end
      run
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(request_key: request_key)
  end

  ACTIVE_STATUSES = %w[queued fetching].freeze
  scope :active, -> { where(status: ACTIVE_STATUSES) }

  # Queues the next page read. The job claims the page again, so duplicate clicks or jobs read at most once.
  def enqueue_page!(expected_page:)
    raise X::Client::Error, "Live collection is disabled in demo mode." if Rails.configuration.x.demo
    queued = with_lock do
      next false unless page_number == expected_page && %w[ready partial paused].include?(status)
      next false if retry_at && retry_at > Time.current
      raise X::Client::Error, "Another X page is already being collected." if self.class.active.where(owner_x_id: owner_x_id).where.not(id: id).exists?
      update!(status: "queued", message: nil)
      true
    end
    X::FetchPageJob.perform_later(workspace, id, expected_page) if queued
    queued
  end

  def fetch_page!(expected_page:)
    raise X::Client::Error, "Live collection is disabled in demo mode." if Rails.configuration.x.demo
    claim = with_lock do
      next false unless page_number == expected_page && %w[ready partial paused queued].include?(status)
      next false if retry_at && retry_at > Time.current
      raise X::Client::Error, "Another X page is already being collected." if self.class.where(owner_x_id: owner_x_id, status: "fetching").where.not(id: id).exists?
      update!(status: "fetching", message: nil, retry_at: nil)
      true
    end
    return false unless claim
    if parameters["start_time"] && Time.iso8601(parameters["start_time"]) >= upper_bound
      update!(status: "completed", finished_at: Time.current, message: "No new time window is available yet; no X read was made.")
      return true
    end
    connection = X::Connection.current
    raise X::Client::Error, "Reconnect the original X account before continuing." unless connection && connection.x_user_id == owner_x_id && owner_x_id == Current.workspace.owner_x_id
    read = x_reads.where(status: "received").order(:id).last
    unless read
      access_token = connection.access_token!
      read = X::Read.fetch!(dataset: dataset, limit: page_limit, run: self) do
        X::Client.new.page(access_token, owner_id: owner_x_id, dataset: dataset, limit: page_limit,
          cursor: cursor, since_id: since_id, upper_bound: upper_bound, parameters: parameters)
      end
    end
    apply_page!(read)
    true
  rescue X::BillingCycle::LimitExceeded, X::Client::Error, X::TokenVault::Unavailable => error
    update!(status: "paused", message: error.message, retry_at: error.respond_to?(:retry_at) ? error.retry_at : nil) if claim
    false
  rescue ActiveRecord::RecordNotUnique
    false
  rescue StandardError
    update!(status: "paused", message: "The saved page could not be applied. Existing data and cost reservations are preserved.") if claim
    raise
  end

  def recover!
    with_lock do
      raise X::Client::Error, "Wait two minutes before recovering an interrupted request." if ACTIVE_STATUSES.include?(status) && updated_at > 2.minutes.ago
      x_reads.where(status: "reserved").update_all(status: "uncertain", message: "Interrupted request; reservation retained.")
      update!(status: "paused", message: "Interrupted collection recovered. Saved responses can be applied without a new read.")
    end
  end

  def apply_page!(read)
    transaction do
      lock!
      return if read.reload.status == "committed"
      payload = read.payload
      if follow_snapshot
        payload.fetch("data").each do |row|
          person = Person.resolve_profile!(Person.profile_from_x(row))
          follow_snapshot.follow_memberships.find_or_create_by!(person: person)
        end
      elsif dataset == "users"
        payload.fetch("data").each do |row|
          Person.resolve_profile!(Person.profile_from_x(row)) unless row.fetch("id") == owner_x_id
        end
      elsif dataset == "dm_events"
        captured = payload.fetch("data").map { |row| DirectMessage.capture!(row, run: self) }
      elsif Engagement::KINDS.key?(dataset)
        observed_after = parameters["observed_after"] && Time.iso8601(parameters["observed_after"])
        captured = payload.fetch("data").map { |row| Engagement.capture!(row, kind: Engagement::KINDS.fetch(dataset), run: self, observed_after: observed_after) }
      else
        payload.fetch("data").each { |row| X::SourcePost.capture!(row, run: self) }
      end
      next_cursor = payload.fetch("meta", {})["next_token"]
      partial_error = payload["partial_errors"] || (next_cursor.present? && next_cursor == cursor)
      # Newest-first sources: a refresh that reaches already-stored evidence has closed the gap.
      reached_known = mode == "refresh" && Array(captured).include?(:known)
      terminal = (next_cursor.blank? || reached_known) && !partial_error
      if follow_snapshot && terminal
        follow_snapshot.update!(completed_at: Time.current)
        Follow::FollowerPeriod.observe!(follow_snapshot)
      end
      update!(cursor: next_cursor, page_number: page_number + 1, resource_count: resource_count + read.resource_count,
        status: terminal ? "completed" : (partial_error ? "paused" : "partial"), finished_at: terminal ? Time.current : nil,
        message: partial_error ? "X returned partial errors. Coverage remains incomplete; start a new snapshot to retry safely." : nil)
      read.mark_applied!
      X::SourcePost.reconcile_all!
      Draft.link_published! if %w[own_posts].include?(dataset)
    end
  end

  def self.unresolved_user_ids
    ids = X::SourcePost.pluck(:author_x_id, :reply_to_x_id).flatten.compact.uniq
    ids += DirectMessage.distinct.pluck(:partner_x_id)
    ids.uniq - Person.where.not(x_id: nil).pluck(:x_id) - [Current.workspace.owner_x_id]
  end

  def self.unresolved_parent_ids
    X::SourcePost.where.not(parent_x_id: nil).pluck(:parent_x_id).uniq - X::SourcePost.pluck(:x_id)
  end
end
