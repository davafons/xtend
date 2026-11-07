# One batch of x.com GraphQL responses that the browser extension observed while the owner browsed.
# Captures cost nothing and make no X requests, but they only cover what was on screen: they never complete
# a follow snapshot or a like/bookmark backfill, and they never count as proof that something didn't happen.
#
# People are added only when the owner showed interest: authors of timeline, search, profile, liked, and
# bookmarked posts, and anyone in a reply exchange with the owner. Other profiles only refresh existing people.
class X::Capture
  class Rejected < StandardError; end
  MAX_RESPONSES = 100
  MAX_RESPONSE_BYTES = 4.megabytes
  ENGAGEMENT_KINDS = { likes: "like", bookmarks: "bookmark" }.freeze

  def self.ingest!(...) = new(...).ingest!

  def initialize(batch_key:, viewer_x_id:, responses:)
    raise Rejected, "Capture is disabled in the demo workspace." if Rails.configuration.x.demo
    raise Rejected, "Invalid batch key." unless batch_key.is_a?(String) && batch_key.match?(/\A[\w-]{16,64}\z/)
    @owner = Current.workspace.owner_x_id
    raise Rejected, "Connect your X account in the CRM first." if @owner.blank?
    raise Rejected, "The browser is signed in to a different X account than this workspace." unless viewer_x_id.to_s == @owner
    # An empty batch is the extension's connection test: it checks the token and the signed-in X account.
    raise Rejected, "Send at most #{MAX_RESPONSES} responses per batch." unless responses.is_a?(Array) && responses.size <= MAX_RESPONSES
    @batch_key = batch_key
    @payloads = responses.filter_map { |response| parse(response) }
    @result = Hash.new(0).merge(responses: responses.size, ignored: responses.size - @payloads.size)
    @runs = {}
    @counts = Hash.new(0)
  end

  def ingest!
    posts = @payloads.map { |payload, _| payload.posts }.reduce({}, :merge)
    profiles = @payloads.map { |payload, _| payload.profiles }.reduce({}, :merge)
    @result[:skipped] = @payloads.sum { |payload, _| payload.skipped }
    ActiveRecord::Base.transaction do
      save_profiles(profiles, addable_people(posts))
      touched = save_posts(posts)
      save_engagements(posts)
      reconcile(touched)
      Draft.link_published! if posts.each_value.any? { |row| row["author_id"] == @owner }
      @runs.each { |key, run| run.update!(resource_count: @counts[key], page_limit: @counts[key].clamp(1, 1000)) }
    end
    @result
  end

  private

  def parse(response)
    return unless response.is_a?(Hash) && X::WebPayload::OPERATIONS.key?(response["operation"])
    body = response["body"]
    return unless body.is_a?(String) && body.bytesize <= MAX_RESPONSE_BYTES
    payload = X::WebPayload.new(response["operation"], JSON.parse(body))
    purpose = payload.purpose
    # Only the owner's own Likes page is evidence of the owner's likes.
    purpose = :context if purpose == :likes && response.dig("variables", "userId").to_s != @owner
    [payload, purpose]
  rescue JSON::ParserError
    nil
  end

  def addable_people(posts)
    ids = Set.new
    @payloads.each do |payload, purpose|
      case purpose
      when :discovery, :likes, :bookmarks then ids.merge(payload.entry_post_ids.filter_map { |id| posts.dig(id, "author_id") })
      when :profile then ids.merge(payload.profiles.keys)
      end
    end
    posts.each_value do |row|
      ids << row["in_reply_to_user_id"] if row["author_id"] == @owner
      ids << row["author_id"] if row["in_reply_to_user_id"] == @owner
    end
    ids.delete(@owner)
    ids
  end

  def save_profiles(profiles, addable)
    known = Person.where(x_id: profiles.keys).pluck(:x_id).to_set
    profiles.each_value do |row|
      next if row["id"] == @owner || !(known.include?(row["id"]) || addable.include?(row["id"]))
      Person.resolve_profile!(Person.profile_from_x(row))
      @result[known.include?(row["id"]) ? :people_updated : :people_added] += 1
    end
  end

  # Keeps the owner's posts, replies to the owner, and posts by people already in the CRM.
  def save_posts(posts)
    known = Person.where(x_id: posts.each_value.map { |row| row["author_id"] }.uniq).pluck(:x_id).to_set
    listed = @payloads.select { |_, purpose| purpose == :discovery }.flat_map { |payload, _| payload.entry_post_ids }.to_set
    posts.each_value.filter_map do |row|
      next unless row["author_id"] == @owner || row["in_reply_to_user_id"] == @owner || known.include?(row["author_id"])
      purpose = listed.include?(row["id"]) && row["author_id"] != @owner ? "discovery" : "context"
      X::SourcePost.capture!(row, run: run("posts", purpose))
      @result[:posts] += 1
      row["id"]
    end
  end

  def save_engagements(posts)
    @payloads.each do |payload, purpose|
      next unless (kind = ENGAGEMENT_KINDS[purpose])
      payload.entry_post_ids.each do |id|
        next unless (row = posts[id])
        state = Engagement.capture!(row, kind: kind, run: run(Engagement::KINDS.key(kind)))
        @result[kind.pluralize.to_sym] += 1 if state == :new
      end
    end
  end

  # Reconciles only this batch and posts that reply to it. A conflicting reply is skipped, not fatal,
  # so one bad item cannot block every later batch.
  def reconcile(ids)
    X::SourcePost.where(x_id: ids).or(X::SourcePost.where(parent_x_id: ids)).includes(:x_sync_run).find_each do |post|
      ActiveRecord::Base.transaction(requires_new: true) { post.reconcile! }
    rescue ArgumentError, ActiveRecord::RecordInvalid
      @result[:conflicts] += 1
    end
  end

  def run(dataset, purpose = nil)
    key = [dataset, purpose].compact.join("-")
    @counts[key] += 1
    @runs[key] ||= X::SyncRun.find_or_create_by!(request_key: "capture-#{@batch_key}-#{key}") do |run|
      now = Time.current.change(usec: 0)
      run.assign_attributes(dataset: dataset, mode: "capture", status: "completed", owner_x_id: @owner,
        page_limit: 1, page_number: 1, upper_bound: now, finished_at: now, parameters: purpose ? { "purpose" => purpose } : {})
    end
  end
end
