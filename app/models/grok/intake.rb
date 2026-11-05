# Accepts research from Grok Bot, either through the MCP connector or a pasted JSON block.
# Grok data is research, not evidence: it never creates replies, follow state, progress, or coverage,
# and it never overwrites X-sourced fields or the owner's edits.
class Grok::Intake
  class Invalid < StandardError; end
  FORMAT = "twitter-crm-grok-v1"
  MAX_ITEMS = 20
  MAX_BYTES = 100.kilobytes
  HOSTS = %w[x.com www.x.com twitter.com www.twitter.com mobile.twitter.com mobile.x.com].freeze
  PROFILE_FIELDS = %w[name description location website_url followers_count following_count].freeze

  def self.status_url(value)
    uri = URI.parse(value.to_s.strip)
    match = uri.path.to_s.match(%r{\A/([A-Za-z0-9_]{1,15}|i/web)/status/(\d{1,30})/?\z})
    return unless HOSTS.include?(uri.host) && %w[http https].include?(uri.scheme) && uri.userinfo.nil? && match
    handle = match[1] == "i/web" ? nil : match[1].downcase
    { handle: handle, x_id: match[2] }
  rescue URI::InvalidURIError
    nil
  end

  # Extracts the versioned document from pasted Grok output, which may wrap it in prose or a code fence.
  def self.parse_paste(text)
    raise Invalid, "Paste up to 100 KB of Grok output." unless text.is_a?(String) && text.bytesize <= MAX_BYTES
    start = text.index(/\{\s*"format"\s*:/)
    raise Invalid, "No #{FORMAT} JSON block was found." unless start
    finish = text.length
    while (finish = text.rindex("}", finish - 1)) && finish > start
      document = JSON.parse(text[start..finish]) rescue next
      raise Invalid, "Use a #{FORMAT} document." unless document.is_a?(Hash) && document["format"] == FORMAT
      return document
    end
    raise Invalid, "The Grok JSON block could not be read. Ask Grok to repeat it without changes."
  end

  def initialize(via:, run_id: nil)
    @via = via
    @run_id = run_id.presence&.to_s&.first(80) || SecureRandom.uuid
  end
  attr_reader :run_id

  def call(document)
    {
      run_id: run_id,
      posts: Array.wrap(document["posts"]).then { |rows| bounded(rows) }.map { |row| post(row) },
      profiles: Array.wrap(document["profiles"]).then { |rows| bounded(rows) }.map { |row| profile(row) },
      recaps: Array.wrap(document["recaps"]).then { |rows| bounded(rows) }.map { |row| recap(row) }
    }
  end

  def post(row)
    return rejected("Each post must be an object.") unless row.is_a?(Hash)
    link = self.class.status_url(row["url"])
    return rejected("Use a public x.com status URL.", row["url"]) unless link
    handle = row["author_handle"].to_s.delete_prefix("@").downcase.strip.presence
    return rejected("The URL handle and author_handle disagree.", row["url"]) if link[:handle] && handle && link[:handle] != handle
    handle ||= link[:handle]
    return rejected("author_handle is required for i/web links.", row["url"]) unless handle&.match?(/\A[a-z0-9_]{1,15}\z/)
    return rejected("Automated accounts are excluded.", row["url"]) if handle == "grok"
    text = row["text"].to_s.strip
    return rejected("Post text is required.", row["url"]) if text.empty?
    published_at = time(row["published_at"])
    return rejected("published_at must be an ISO-8601 time in the past 30 days.", row["url"]) unless published_at && published_at.between?(30.days.ago, 1.minute.from_now)

    existing = Post.find_by(x_id: link[:x_id])
    return result("already_verified", link[:x_id], "Collected from X; Grok fields were not applied.") if existing && existing.source != "grok"
    if ReplyEvent.exists?(direction: "outgoing", target_x_id: link[:x_id]) || Outreach.exists?(target_x_id: link[:x_id])
      return result("already_replied", link[:x_id], "You already replied to this post.")
    end

    Post.transaction do
      person = author(handle, row)
      assessment = Discovery::Assessment.call(body: text, description: person.description,
        interests: Workspace.current.interests, handle: handle, selected: true)
      reason = row["match_reason"].to_s.strip.first(500).presence
      record = existing || Post.new(x_id: link[:x_id])
      record.assign_attributes(person: person, body: text.first(1000), language: row["language"].to_s.presence&.first(8) || "en",
        published_at: [published_at, Time.current].min, reply_count: integer(row["reply_count"]), topic: "Grok research",
        match_reason: assessment[:rank].negative? ? assessment[:reason] : (reason ? "Grok: #{reason}" : "Grok suggested this post; no reason given."),
        rank: assessment[:rank], source: "grok", grok_run_id: run_id)
      record.save!
      result(existing ? "updated" : "created", link[:x_id], assessment[:rank].negative? ? assessment[:reason] : nil)
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    rejected("Could not save: #{error.message}", row.is_a?(Hash) ? row["url"] : nil)
  end

  def profile(row)
    return rejected("Each profile must be an object.") unless row.is_a?(Hash)
    person = find_person(row)
    return rejected("Unknown person. Use a person_id or handle the CRM already has.", row["handle"]) unless person
    facts = profile_facts(row)
    return rejected("No supported profile fields were given.", person.handle) if facts.empty?
    observed_at = time(row["observed_at"]) || Time.current
    Grok::Proposal.transaction do
      Grok::Proposal.pending.where(person: person, kind: "profile").destroy_all
      proposal = Grok::Proposal.create!(person: person, kind: "profile", via: @via, run_id: run_id,
        payload: facts.merge("observed_at" => [observed_at, Time.current].min.iso8601))
      result("staged", person.handle, "Proposal #{proposal.id} awaits review.")
    end
  end

  def recap(row)
    return rejected("Each recap must be an object.") unless row.is_a?(Hash)
    person = find_person(row)
    return rejected("Unknown person. Use a person_id or handle the CRM already has.", row["handle"]) unless person
    summary = row["summary"].to_s.strip
    return rejected("summary must be 1 to 1,500 characters.", person.handle) unless summary.length.between?(1, 1500)
    urls = Array.wrap(row["evidence_urls"]).first(10).map(&:to_s)
    return rejected("evidence_urls must be public x.com status URLs.", person.handle) unless urls.all? { |url| self.class.status_url(url) }
    proposal = Grok::Proposal.create!(person: person, kind: "recap", via: @via, run_id: run_id,
      payload: { "summary" => summary, "evidence_urls" => urls })
    result("staged", person.handle, "Proposal #{proposal.id} awaits review.")
  end

  private

  def bounded(rows)
    raise Invalid, "Send up to #{MAX_ITEMS} items of each kind at a time." if rows.size > MAX_ITEMS
    rows
  end

  # Unknown authors become Grok-only people without a numeric X ID. Their Grok profile is labeled
  # on screen and gets bound to the real X ID once an X read connects them to a post.
  def author(handle, row)
    person = Person.find_by(handle: handle)
    facts = profile_facts("name" => row["author_name"], "description" => row["author_bio"], "followers_count" => row["author_followers_count"])
    if person.nil?
      Person.create!(facts.reverse_merge("name" => handle).merge(handle: handle))
    else
      person.fill_blank_profile!(facts) if person.x_id.nil?
      person
    end
  end

  def find_person(row)
    if row["person_id"].present?
      Person.find_by(id: row["person_id"])
    elsif row["handle"].present?
      Person.find_by(handle: row["handle"].to_s.delete_prefix("@").downcase.strip)
    end
  end

  def profile_facts(row)
    facts = {}
    %w[name description location].each { |key| facts[key] = row[key].to_s.strip.first(key == "description" ? 500 : 100) if row[key].present? }
    facts["website_url"] = row["website_url"].to_s if row["website_url"].to_s.match?(%r{\Ahttps?://[^\s]{1,300}\z})
    %w[followers_count following_count].each { |key| facts[key] = integer(row[key]) if integer(row[key]) }
    facts
  end

  def integer(value)
    number = Integer(value, exception: false) if value.is_a?(Integer) || value.to_s.match?(/\A\d{1,12}\z/)
    number if number&.>= 0
  end

  def time(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  def result(status, ref, message = nil)
    { status: status, ref: ref, message: message }.compact
  end

  def rejected(message, ref = nil)
    result("rejected", ref, message)
  end
end
