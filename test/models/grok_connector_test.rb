require "test_helper"

class GrokConnectorTest < ActiveSupport::TestCase
  def candidate(url: "https://x.com/newbuilder/status/8101", **overrides)
    { "url" => url, "author_handle" => "newbuilder", "author_name" => "New Builder", "author_bio" => "Rails and SQLite",
      "author_followers_count" => 1200, "text" => "How do you test Rails jobs that touch SQLite?",
      "published_at" => 2.hours.ago.iso8601, "reply_count" => 3, "match_reason" => "Asks a concrete Rails testing question" }.merge(overrides)
  end

  def intake(rows)
    Grok::Intake.new(via: "mcp").call("posts" => rows)
  end

  def sync_run(dataset, mode: "refresh", parameters: {})
    X::SyncRun.create!(owner_x_id: "999", dataset: dataset, mode: mode, page_limit: 10, upper_bound: Time.current,
      request_key: SecureRandom.uuid, parameters: parameters)
  end

  def reply_row(id:, parent:, to:, conversation:)
    { "id" => id, "author_id" => "999", "text" => "Useful reply", "created_at" => 1.minute.ago.iso8601, "lang" => "en",
      "in_reply_to_user_id" => to, "conversation_id" => conversation, "referenced_posts" => [{ "type" => "replied_to", "id" => parent }] }
  end

  test "a Grok candidate reaches Today unverified without X reads, replies, or progress" do
    result = intake([candidate])
    assert_equal "created", result[:posts].first[:status]
    post = Post.find_by!(x_id: "8101")
    assert_equal "grok", post.source
    assert_includes Post.opportunities, post
    assert_equal "AI: Asks a concrete Rails testing question", post.match_reason
    person = post.person
    assert_nil person.x_id
    assert person.grok_only?
    assert_equal ["New Builder", "Rails and SQLite", 1200], [person.name, person.description, person.followers_count]
    assert_equal 0, X::Read.count
    assert_equal 0, ReplyEvent.count
    assert_equal 0, DailySession.current.progress
  end

  test "invalid or fabricated-looking candidates are rejected item by item" do
    result = intake([
      candidate(url: "https://x.com.evil.example/newbuilder/status/1"),
      candidate(url: "https://x.com/someone/status/8102"),
      candidate(url: "https://x.com/grok/status/8103", "author_handle" => "grok"),
      candidate(url: "https://x.com/newbuilder/status/8104", "published_at" => 1.day.from_now.iso8601),
      candidate(url: "https://x.com/newbuilder/status/8105", "text" => " "),
      candidate(url: "https://x.com/newbuilder/status/8106")
    ])
    assert_equal %w[rejected rejected rejected rejected rejected created], result[:posts].map { |item| item[:status] }
    assert_equal ["8106"], Post.pluck(:x_id)
    assert_raises(Grok::Intake::Invalid) { intake(Array.new(21) { |index| candidate(url: "https://x.com/newbuilder/status/#{9000 + index}") }) }
  end

  test "Grok never overwrites X-collected posts, profiles, or the owner's choices" do
    person = Person.resolve_profile!(profile(x_id: "555", handle: "newbuilder", name: "Real Name"))
    person.update!(notes: "Met at RubyKaigi", description: "From X")
    person.create_pin!
    person.posts.create!(x_id: "8101", body: "Collected from X", published_at: 1.hour.ago)
    ingest(target_x_id: "8102", person_profile: profile(x_id: "555", handle: "newbuilder", name: "Real Name"))
    result = intake([candidate, candidate(url: "https://x.com/newbuilder/status/8102"), candidate(url: "https://x.com/newbuilder/status/8103", "author_bio" => "Grok bio")])
    assert_equal %w[already_verified already_replied created], result[:posts].map { |item| item[:status] }
    assert_equal "Collected from X", Post.find_by!(x_id: "8101").body
    person.reload
    assert_equal ["Real Name", "From X", "Met at RubyKaigi"], [person.name, person.description, person.notes]
    assert person.pin.present?
  end

  test "a sent reply to a Grok target binds the author and counts once as a new target" do
    intake([candidate])
    reply = sync_run("own_posts")
    X::SourcePost.capture!(reply_row(id: "7101", parent: "8101", to: "555", conversation: "8101"), run: reply)
    X::SourcePost.reconcile_all!
    person = Person.find_by!(handle: "newbuilder")
    assert_equal "555", person.x_id
    event = ReplyEvent.find_by!(x_id: "7101")
    assert_equal ["outgoing", "initial", person.id], [event.direction, event.classification, event.person_id]
    assert_equal 1, DailySession.current.progress
    assert_not_includes Post.opportunities, Post.find_by!(x_id: "8101")

    X::SourcePost.capture!(reply_row(id: "7102", parent: "7101", to: "555", conversation: "8101"), run: reply)
    X::SourcePost.reconcile_all!
    assert_equal 1, DailySession.current.progress
  end

  test "a reply to a Grok post inside the owner's own thread is a follow-up" do
    own = sync_run("own_posts", mode: "backfill")
    X::SourcePost.capture!({ "id" => "6000", "author_id" => "999", "text" => "My thread", "created_at" => 1.day.ago.iso8601, "lang" => "en", "referenced_posts" => [] }, run: own)
    intake([candidate])
    X::SourcePost.capture!(reply_row(id: "7101", parent: "8101", to: "555", conversation: "6000"), run: sync_run("own_posts"))
    X::SourcePost.reconcile_all!
    assert_equal "continuation", ReplyEvent.find_by!(x_id: "7101").classification
    assert_equal 0, DailySession.current.progress
  end

  test "verifying a Grok post on X replaces reported facts and keeps Grok's reason" do
    intake([candidate])
    lookup = sync_run("posts", mode: "capture", parameters: { "ids" => ["8101"], "purpose" => "discovery" })
    X::SourcePost.capture!({ "id" => "8101", "author_id" => "555", "text" => "How do you test Rails jobs on SQLite?", "created_at" => 3.hours.ago.iso8601,
      "lang" => "en", "referenced_posts" => [], "reply_count" => 5 }, run: lookup)
    X::SourcePost.reconcile_all!
    post = Post.find_by!(x_id: "8101")
    assert_equal ["x_capture", "555", "How do you test Rails jobs on SQLite?", 5], [post.source, post.person.x_id, post.body, post.reply_count]
    assert_equal "AI: Asks a concrete Rails testing question", post.match_reason
  end

  test "verification that names a different known author moves the post" do
    real = Person.resolve_profile!(profile(x_id: "777", handle: "realauthor", name: "Real Author"))
    intake([candidate])
    lookup = sync_run("posts", mode: "capture", parameters: { "ids" => ["8101"], "purpose" => "discovery" })
    X::SourcePost.capture!({ "id" => "8101", "author_id" => "777", "text" => "Rails jobs question", "created_at" => 3.hours.ago.iso8601,
      "lang" => "en", "referenced_posts" => [] }, run: lookup)
    X::SourcePost.reconcile_all!
    assert_equal real, Post.find_by!(x_id: "8101").person
    assert_nil Person.find_by!(handle: "newbuilder").x_id
  end

  test "profile proposals fill only empty fields and recaps need acceptance" do
    person = Person.resolve_profile!(profile(x_id: "555", handle: "newbuilder", name: "Real Name"))
    person.update!(description: "From X")
    result = Grok::Intake.new(via: "mcp").call(
      "profiles" => [{ "handle" => "newbuilder", "description" => "Grok bio", "location" => "Tokyo", "followers_count" => 900 }, { "handle" => "unknown" }],
      "recaps" => [{ "person_id" => person.id, "summary" => "Builds Rails tools.", "evidence_urls" => ["https://x.com/newbuilder/status/1"] },
        { "person_id" => person.id, "summary" => "Bad evidence", "evidence_urls" => ["https://evil.example/1"] }])
    assert_equal ["staged", "rejected"], result[:profiles].map { |item| item[:status] }
    assert_equal ["staged", "rejected"], result[:recaps].map { |item| item[:status] }
    assert_nil person.reload.location
    assert_nil person.grok_proposals.latest_recap

    person.grok_proposals.pending.each(&:accept!)
    person.reload
    assert_equal ["From X", "Tokyo", 900], [person.description, person.location, person.followers_count]
    assert_equal "Builds Rails tools.", person.grok_proposals.latest_recap.payload["summary"]
    assert_equal 0, ReplyEvent.count
  end

  test "pasted Grok answers are read from the JSON block inside prose" do
    text = "Here are posts {not json}.\n```json\n{\"format\": \"twitter-crm-grok-v1\", \"posts\": [#{candidate.to_json}]}\n```\nHope this helps {really}."
    document = Grok::Intake.parse_paste(text)
    assert_equal 1, Grok::Intake.new(via: "paste").call(document)[:posts].count { |item| item[:status] == "created" }
    assert_raises(Grok::Intake::Invalid) { Grok::Intake.parse_paste("no block here") }
    assert_raises(Grok::Intake::Invalid) { Grok::Intake.parse_paste('{"format": "other", "posts": []}') }
  end
end
