# Reads a downloaded X archive zip: the owner's own posts and replies, and one-to-one DM metadata. Only the
# manifest, account, tweets, and DM files are opened; DM text is never read into storage and encrypted chat
# contents stay encrypted. The archive is a snapshot as of its generation date, so nothing here speaks for later.
class X::ArchiveImport < ApplicationRecord
  include WorkspaceScoped
  self.table_name = "x_archive_imports"
  class Invalid < StandardError; end
  MAX_ENTRY_BYTES = 200.megabytes
  FILE_NAME = %r{\Adata/[a-z0-9-]+\.js\z}
  CHUNK = 1_000
  # Reconciling a reply takes a few milliseconds, so smaller chunks keep each write lock short for captures.
  REPLY_CHUNK = 200
  TWEET_TIME = "%a %b %d %H:%M:%S %z %Y"
  STALE = 1.hour

  STATUSES = %w[queued importing completed failed].freeze

  validates :owner_x_id, :generated_at, :account_created_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  # Checks the archive belongs to this workspace, keeps the upload, and imports it in the background: a large
  # archive takes longer than a web request should. Until it completes the import counts as partial, so DM
  # coverage is never claimed for data that isn't in yet.
  def self.start!(path)
    running = where(status: %w[queued importing])
    running.where(updated_at: ...STALE.ago).find_each { |stuck| stuck.update!(status: "failed", message: "The import didn't finish. Anything already added is kept; importing the archive again finishes it.") }
    raise Invalid, "An archive import is already running. Wait for it to finish." if running.exists?
    import = prepare(path)
    import.update!(status: "queued", partial: true)
    FileUtils.mkdir_p(File.dirname(import.upload_path))
    FileUtils.cp(path, import.upload_path)
    X::ArchiveImportJob.perform_later(Current.workspace, import.id)
    import
  end

  # Imports in the caller's process; the background job and tests use this.
  def self.import!(path)
    prepare(path).tap { |import| import.import_from!(path) }
  end

  def self.prepare(path)
    owner = Current.workspace.owner_x_id
    raise Invalid, "Connect your X account first so the archive can be matched to it." if owner.blank?
    readable do
      Zip::File.open(path) do |zip|
        manifest = read(zip, "data/manifest.js")
        account = manifest_files(manifest, "account").flat_map { |name| read(zip, name) }.first&.fetch("account")
        raise Invalid, "This archive has no account file." unless account
        raise Invalid, "This archive belongs to a different X account. Nothing was imported." unless account.fetch("accountId") == owner
        new(owner_x_id: owner, generated_at: Time.iso8601(manifest.fetch("archiveInfo").fetch("generationDate")),
          account_created_at: Time.iso8601(account.fetch("createdAt")), partial: true)
      end
    end
  end

  def self.readable
    yield
  rescue Zip::Error
    raise Invalid, "Choose the .zip file X sent you."
  rescue JSON::ParserError, KeyError, ArgumentError, TypeError, NoMethodError, ActiveRecord::RecordInvalid
    raise Invalid, "The archive could not be read. Nothing was imported."
  end

  # Run by X::ArchiveImportJob. A run interrupted by a restart is picked up again; the import is idempotent.
  def run!
    return unless %w[queued importing].include?(status)
    update!(status: "importing")
    import_from!(upload_path)
  rescue Invalid => error
    update!(status: "failed", message: error.message)
  rescue StandardError
    update!(status: "failed", message: "The import stopped unexpectedly. Anything already added is kept; importing the archive again finishes it.")
    raise
  ensure
    FileUtils.rm_f(upload_path) unless status == "importing"
  end

  # Every file is read before anything is written, so an unreadable archive changes nothing.
  def import_from!(path)
    self.class.readable do
      Zip::File.open(path) do |zip|
        manifest = self.class.read(zip, "data/manifest.js")
        posts, repliees = self.class.read_posts(zip, manifest, owner_x_id)
        conversations = self.class.manifest_files(manifest, "directMessages").flat_map { |name| self.class.read(zip, name) }
        events = self.class.manifest_files(manifest, "messageEvent").flat_map { |name| self.class.read(zip, name) }
        counts = self.class.import_posts(posts, repliees, owner: owner_x_id, generated_at: generated_at)
        transaction do
          dms = self.class.import_direct_messages(conversations, events)
          update!(status: "completed", message: nil, partial: manifest.fetch("archiveInfo")["isPartialArchive"] != false,
            direct_messages_count: dms[:new], skipped_count: dms[:skipped], **counts)
        end
      end
    end
  end

  def upload_path
    File.join(File.dirname(Rails.root.join(self.class.connection_db_config.database)), "archive_uploads", "#{workspace_id}-#{id}.zip")
  end

  def in_progress? = %w[queued importing].include?(status)

  def self.import_direct_messages(conversations, events)
    counts = Hash.new(0)
    conversations.each do |item|
      conversation = item.fetch("dmConversation")
      participants = conversation.fetch("conversationId").split("-")
      conversation.fetch("messages").each do |message|
        data = message["messageCreate"] or next
        counts[DirectMessage.record!(x_id: data.fetch("id"), conversation_x_id: conversation.fetch("conversationId"), participants: participants,
          sender_x_id: data.fetch("senderId"), occurred_at: Time.iso8601(data.fetch("createdAt")), source: "archive")] += 1
      end
    end
    events.each do |item|
      event = item.fetch("messageEvent")
      next unless event.fetch("detail").key?("messageCreateEvent")
      counts[DirectMessage.record!(x_id: event.fetch("messageId"), conversation_x_id: event.fetch("conversationId"),
        participants: event.fetch("conversationId").split(":"), sender_x_id: event.fetch("senderId"),
        occurred_at: Time.at(Integer(event.fetch("createdAtMsec")) / 1000r), source: "archive")] += 1
    end
    counts
  end

  # The owner's posts as source post rows, and who each reply went to. The archive names a repliee only by the
  # handle they had then and, when X added it, their display name; later captures fill in the rest.
  def self.read_posts(zip, manifest, owner)
    posts = {}
    repliees = {}
    manifest_files(manifest, "tweets").each do |name|
      read(zip, name).each do |item|
        tweet = item.fetch("tweet")
        row = post_row(tweet, owner)
        posts[row[:x_id]] = row
        target = row[:reply_to_x_id]
        next if target.nil? || target == owner || row[:repost]
        handle = tweet["in_reply_to_screen_name"].to_s.downcase
        next unless handle.match?(/\A[a-z0-9_]{1,15}\z/) && target.match?(/\A\d{1,30}\z/)
        next if repliees[target] && repliees[target][:at] > row[:published_at]
        mention = Array(tweet.dig("entities", "user_mentions")).find { |user| user["id_str"] == target }
        repliees[target] = { handle: handle, name: mention&.dig("name").presence || handle, at: row[:published_at] }
      end
    end
    [ posts.values, repliees ]
  end

  def self.post_row(tweet, owner)
    text = tweet.fetch("full_text")
    x_id = tweet.fetch("id_str")
    raise ArgumentError, "Archive post IDs are numeric." unless x_id.match?(/\A\d{1,30}\z/)
    repost = text.start_with?("RT @")
    parent = tweet["in_reply_to_status_id_str"].presence unless repost
    media = Array(tweet.dig("extended_entities", "media") || tweet.dig("entities", "media")).filter_map { |item| item["type"] }
    links = Array(tweet.dig("entities", "urls")).any? { |url| !url["expanded_url"].to_s.match?(%r{\Ahttps?://(x|twitter)\.com/\w+/status/}) }
    { x_id: x_id, author_x_id: owner, parent_x_id: parent, reply_to_x_id: (tweet["in_reply_to_user_id_str"].presence if parent),
      body: text, language: tweet["lang"], published_at: Time.strptime(tweet.fetch("created_at"), TWEET_TIME).utc, repost: repost,
      like_count: (Integer(tweet["favorite_count"]) unless repost || tweet["favorite_count"].nil?),
      repost_count: (Integer(tweet["retweet_count"]) unless repost || tweet["retweet_count"].nil?),
      media_kinds: (media.uniq.sort.join(",").presence unless repost), has_link: !repost && links }
  end

  # Inserts new posts in chunks so a large archive doesn't hold the database for the whole import. Posts already
  # known from X or a capture keep what those saw. Replies then go through the same reconciliation as collected
  # ones, so they become people and reply events with the usual classification.
  def self.import_posts(posts, repliees, owner:, generated_at:)
    return { posts_count: 0, replies_count: 0, people_count: 0 } if posts.empty?
    now = Time.current
    run = X::SyncRun.find_or_create_by!(request_key: "archive-#{owner}-#{generated_at.to_i}") do |record|
      record.assign_attributes(dataset: "own_posts", mode: "archive", status: "completed", owner_x_id: owner, page_limit: 1,
        page_number: 1, resource_count: posts.size, upper_bound: generated_at, finished_at: now,
        message: "From your X archive, generated #{generated_at.to_date.to_fs(:long)}.")
    end
    defaults = { x_sync_run_id: run.id, workspace_id: Current.workspace.id, first_seen_at: generated_at, created_at: now, updated_at: now }
    inserted = posts.each_slice(CHUNK).sum do |slice|
      rows = slice.map { |row| row.merge(defaults, metrics_observed_at: (generated_at if row[:like_count])) }
      transaction { X::SourcePost.insert_all(rows, unique_by: [ :workspace_id, :x_id ], returning: [ :id ]).length }
    end
    people = add_people(repliees)
    replies = posts.select { |row| row[:reply_to_x_id] && row[:reply_to_x_id] != owner }.sort_by { |row| row[:published_at] }
    reply_events = replies.each_slice(REPLY_CHUNK).sum do |slice|
      ids = slice.map { |row| row[:x_id] }
      transaction do
        before = ReplyEvent.where(x_id: ids).count
        # Replies already confirmed settle through captures and reads; only new ones need reconciling here.
        X::SourcePost.where(x_id: ids).where.not(x_id: ReplyEvent.select(:x_id)).includes(:x_sync_run).order(:published_at).each do |post|
          post.record_reply_interaction
          transaction(requires_new: true) { post.reconcile! }
        rescue ArgumentError, ActiveRecord::RecordInvalid
          # A reply already confirmed as another interaction keeps what was confirmed.
        end
        ReplyEvent.where(x_id: ids).count - before
      end
    end
    Draft.link_published!
    { posts_count: inserted, replies_count: reply_events, people_count: people }
  end

  # Creates people the workspace doesn't know yet. A handle another account holds now is left alone: the
  # archive's handle may be years old.
  def self.add_people(repliees)
    missing = repliees.except(*Person.where(x_id: repliees.keys).pluck(:x_id))
    missing.each_slice(CHUNK).sum do |slice|
      transaction do
        slice.count do |x_id, repliee|
          holder = Person.find_by(handle: repliee[:handle])
          next false if holder&.x_id
          profile = { x_id: x_id, handle: repliee[:handle] }
          profile[:name] = repliee[:name] unless holder
          Person.resolve_profile!(profile)
        rescue ActiveRecord::RecordInvalid
          false
        end
      end
    end
  end

  def self.manifest_files(manifest, type)
    Array(manifest.dig("dataTypes", type, "files")).map { |file| file.fetch("fileName") }.each do |name|
      raise Invalid, "The archive manifest lists an unexpected file." unless name.match?(FILE_NAME)
    end
  end

  def self.read(zip, name)
    entry = zip.find_entry(name) or raise Invalid, "The archive is missing #{name}."
    raise Invalid, "#{name} is too large to import." if entry.size > MAX_ENTRY_BYTES
    text = entry.get_input_stream.read(MAX_ENTRY_BYTES + 1)
    raise Invalid, "#{name} is too large to import." if text.bytesize > MAX_ENTRY_BYTES
    JSON.parse(text.sub(/\A\s*window\.[\w.]+\s*=\s*/, "").sub(/;\s*\z/, ""))
  end
  private_class_method :post_row, :add_people

  def summary
    parts = [ pluralize_count(posts_count, "new post"), pluralize_count(replies_count, "new reply", "new replies"),
      pluralize_count(people_count, "person added", "people added"), pluralize_count(direct_messages_count, "new DM") ]
    "#{parts.to_sentence} from your archive of #{generated_at.to_date.to_fs(:long)}"
  end

  private

  def pluralize_count(count, singular, plural = nil)
    "#{count.to_fs(:delimited)} #{count == 1 ? singular : (plural || singular.pluralize)}"
  end
end
