require "test_helper"
require "tmpdir"

class ArchivePostsImportTest < ActiveSupport::TestCase
  GENERATED = 1.hour.ago.change(usec: 0)

  setup { @directory = Dir.mktmpdir }
  teardown do
    X::ArchiveImport.find_each { |import| FileUtils.rm_f(import.upload_path) }
    FileUtils.remove_entry(@directory)
  end

  def archive(tweets:, owner: "999", name: "archive.zip", parts: 1)
    tweet_files = (1..parts).map { |part| "data/tweets#{"-part#{part}" if parts > 1}.js" }
    manifest = { "archiveInfo" => { "generationDate" => GENERATED.iso8601, "isPartialArchive" => false },
      "dataTypes" => {
        "account" => { "files" => [ { "fileName" => "data/account.js" } ] },
        "tweets" => { "files" => tweet_files.map { |file| { "fileName" => file } } },
        "messageEvent" => { "files" => [ { "fileName" => "data/message-event.js" } ] }
      } }
    contents = { "data/manifest.js" => manifest,
      "data/account.js" => [ { "account" => { "accountId" => owner, "createdAt" => 400.days.ago.iso8601 } } ],
      "data/message-event.js" => [ { "messageEvent" => { "messageId" => "m-1", "conversationId" => "101:999", "senderId" => "101",
        "createdAtMsec" => (2.days.ago.to_f * 1000).to_i.to_s, "detail" => { "messageCreateEvent" => { "contents" => "ENCRYPTED" } } } } ] }
    items = tweets.map { |tweet| { "tweet" => tweet } }
    tweet_files.each_with_index { |file, index| contents[file] = items.each_slice((items.size / parts.to_f).ceil.clamp(1, nil)).to_a[index] || [] }
    path = File.join(@directory, name)
    Zip::OutputStream.open(path) do |zip|
      contents.each { |file, value| zip.put_next_entry(file); zip.write("window.YTD.x.part0 = #{JSON.generate(value)}") }
    end
    path
  end

  def tweet(id, at, text: "a post", reply_to: nil, user: nil, handle: nil, name: nil, likes: 3)
    { "id_str" => id, "full_text" => text, "created_at" => at.utc.strftime("%a %b %d %H:%M:%S +0000 %Y"), "lang" => "en",
      "favorite_count" => likes.to_s, "retweet_count" => "1", "retweeted" => false,
      "in_reply_to_status_id_str" => reply_to, "in_reply_to_user_id_str" => user, "in_reply_to_screen_name" => handle,
      "entities" => { "user_mentions" => (user ? [ { "id_str" => user, "screen_name" => handle, "name" => name || handle } ] : []), "urls" => [] } }
  end

  def tweets
    [
      tweet("9001", 30.days.ago, text: "my own post"),
      tweet("9002", 29.days.ago, text: "@ada hello", reply_to: "5001", user: "201", handle: "Ada", name: "Ada L"),
      tweet("9003", 28.days.ago, text: "@ada again", reply_to: "5001", user: "201", handle: "ada", name: "Ada L"),
      tweet("9004", 27.days.ago, text: "thread part 2", reply_to: "9001", user: "999", handle: "owner"),
      tweet("9005", 26.days.ago, text: "RT @grace: hi", likes: 0),
      tweet("9006", 25.days.ago, text: "@grace nice", reply_to: "5002", user: "202", handle: "grace", name: "Grace H")
    ]
  end

  test "posts and replies become people and outgoing archive reply events" do
    import = X::ArchiveImport.import!(archive(tweets: tweets))
    assert_equal [ 6, 3, 2, 1 ], [ import.posts_count, import.replies_count, import.people_count, import.direct_messages_count ]
    assert_equal GENERATED, import.generated_at

    ada = Person.find_by!(x_id: "201")
    assert_equal [ "ada", "Ada L" ], [ ada.handle, ada.name ]
    events = ReplyEvent.order(:occurred_at)
    assert_equal %w[9002 9003 9006], events.map(&:x_id)
    assert_equal %w[archive], events.map(&:source).uniq
    assert_equal %w[outgoing], events.map(&:direction).uniq
    # The archive holds no one else's posts, so a first reply stays unclassified, while a second reply to
    # the same post is a follow-up. Self-replies and reposts are no interaction at all.
    assert_equal %w[unclassified continuation unclassified], events.map(&:classification)
    assert_not events.any?(&:outreach_eligible)
    assert_equal 0, Outreach::Target.count

    repost = X::SourcePost.find_by!(x_id: "9005")
    assert repost.repost
    assert_nil repost.parent_x_id
    assert_nil repost.like_count
    own = X::SourcePost.find_by!(x_id: "9001")
    assert_equal [ 3, GENERATED ], [ own.like_count, own.metrics_observed_at ]
    assert_equal "archive", own.x_sync_run.mode
    assert_empty X::SyncRun.unresolved_parent_ids, "archive replies must not queue paid parent lookups"
  end

  test "a known parent post settles the classification, and a later capture of it would too" do
    run = X::SyncRun.create!(dataset: "posts", mode: "capture", status: "completed", owner_x_id: "999", request_key: "capture-test-parent",
      page_limit: 1, upper_bound: Time.current)
    X::SourcePost.create!(x_id: "5002", author_x_id: "202", body: "root", published_at: 40.days.ago, x_sync_run: run)
    X::ArchiveImport.import!(archive(tweets: tweets))
    event = ReplyEvent.find_by!(x_id: "9006")
    assert_equal "initial", event.classification
    assert_equal event, Outreach::Target.find_by!(target_x_id: "5002").reply_event
  end

  test "importing the same archive twice changes nothing" do
    path = archive(tweets: tweets)
    X::ArchiveImport.import!(path)
    snapshot = -> { [ X::SourcePost.count, ReplyEvent.count, Person.count, DirectMessage.count, X::SyncRun.count, X::Interaction.count ] }
    before = snapshot.call
    again = X::ArchiveImport.import!(path)
    assert_equal [ 0, 0, 0, 0 ], [ again.posts_count, again.replies_count, again.people_count, again.direct_messages_count ]
    assert_equal before, snapshot.call
  end

  test "manual tags, notes, names, and handles survive the import" do
    ada = Person.resolve_profile!(profile(x_id: "201", handle: "ada_now", name: "Ada Lovelace"))
    ada.update!(notes: "met at RailsConf")
    ada.add_tags!("friend")
    ada.create_pin!
    X::ArchiveImport.import!(archive(tweets: tweets))
    ada.reload
    assert_equal [ "ada_now", "Ada Lovelace", "met at RailsConf", [ "friend" ] ], [ ada.handle, ada.name, ada.notes, ada.tags.map(&:name) ]
    assert ada.pin
    assert_equal 2, ada.reply_events.count
  end

  test "a stale handle another account now holds is not taken over" do
    Person.resolve_profile!(profile(x_id: "777", handle: "grace", name: "New Grace"))
    import = X::ArchiveImport.import!(archive(tweets: tweets))
    assert_equal 1, import.people_count
    assert_equal "777", Person.find_by!(handle: "grace").x_id
    assert_nil ReplyEvent.find_by(x_id: "9006")
  end

  test "another account's archive is refused and nothing is written" do
    error = assert_raises(X::ArchiveImport::Invalid) { X::ArchiveImport.import!(archive(tweets: tweets, owner: "555")) }
    assert_match "different X account", error.message
    assert_equal [ 0, 0, 0 ], [ X::SourcePost.count, ReplyEvent.count, Person.count ]
  end

  test "an unreadable tweet file writes nothing" do
    broken = tweets + [ { "id_str" => "9100", "created_at" => "not a date", "full_text" => "x" } ]
    assert_raises(X::ArchiveImport::Invalid) { X::ArchiveImport.import!(archive(tweets: broken)) }
    assert_equal [ 0, 0, 0 ], [ X::SourcePost.count, DirectMessage.count, X::ArchiveImport.count ]
  end

  test "split tweet files are all read and DMs still import without text" do
    import = X::ArchiveImport.import!(archive(tweets: tweets, parts: 3))
    assert_equal 6, import.posts_count
    assert_equal [ "101" ], DirectMessage.distinct.pluck(:partner_x_id)
    assert_not_includes DirectMessage.all.map(&:attributes).to_json, "ENCRYPTED"
    assert_match "6 new posts, 3 new replies, 2 people added, and 1 new DM from your archive of", import.summary
  end

  test "a background import that can't read the archive settles as failed and keeps nothing" do
    import = X::ArchiveImport.start!(archive(tweets: tweets))
    File.write(import.upload_path, "not a zip any more")
    import.run!
    assert_equal [ "failed", "Choose the .zip file X sent you.", true ], [ import.status, import.message, import.partial ]
    assert_not File.exist?(import.upload_path)
    assert_equal 0, X::SourcePost.count
  end

  test "an import stuck for an hour is marked failed so a new upload can start" do
    stuck = X::ArchiveImport.start!(archive(tweets: tweets))
    stuck.update_columns(updated_at: 2.hours.ago)
    X::ArchiveImport.start!(archive(tweets: tweets, name: "again.zip"))
    assert_equal "failed", stuck.reload.status
  end
end
