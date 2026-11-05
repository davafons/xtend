require "test_helper"
require "tmpdir"

class ArchiveImportTest < ActiveSupport::TestCase
  OWNER = "999"

  def archive(owner: OWNER, partial: false, files: {})
    manifest = { "archiveInfo" => { "generationDate" => 1.hour.ago.iso8601, "isPartialArchive" => partial },
      "dataTypes" => {
        "account" => { "files" => [{ "fileName" => "data/account.js" }] },
        "directMessages" => { "files" => [{ "fileName" => "data/direct-messages.js" }] },
        "messageEvent" => { "files" => [{ "fileName" => "data/message-event.js" }] }
      } }
    contents = {
      "data/manifest.js" => manifest,
      "data/account.js" => [{ "account" => { "accountId" => owner, "createdAt" => 200.days.ago.iso8601 } }],
      "data/direct-messages.js" => [{ "dmConversation" => { "conversationId" => "101-999", "messages" => [
        { "messageCreate" => { "id" => "5001", "senderId" => "101", "recipientId" => "999", "text" => "legacy secret", "createdAt" => 90.days.ago.iso8601 } }
      ] } }],
      "data/message-event.js" => [
        event("a-1", "101:999", "999", 3.days.ago),
        event("a-2", "101:999", "101", 2.days.ago),
        event("a-3", "999:999", "999", 1.day.ago),
        { "messageEvent" => { "messageId" => "a-4", "conversationId" => "101:999", "senderId" => "999", "createdAtMsec" => (1.day.ago.to_f * 1000).to_i.to_s,
          "detail" => { "markConversationReadEvent" => { "seenAtMillis" => "1" } } } }
      ]
    }.merge(files)
    path = File.join(@directory, "archive.zip")
    Zip::OutputStream.open(path) do |zip|
      contents.each { |name, value| zip.put_next_entry(name); zip.write("#{name.end_with?('manifest.js') ? 'window.__THAR_CONFIG' : 'window.YTD.x.part0'} = #{JSON.generate(value)}") }
    end
    path
  end

  def event(id, conversation, sender, at)
    { "messageEvent" => { "messageId" => id, "conversationId" => conversation, "senderId" => sender,
      "createdAtMsec" => (at.to_f * 1000).to_i.to_s, "detail" => { "messageCreateEvent" => { "contents" => "ENCRYPTED" } } } }
  end

  setup { @directory = Dir.mktmpdir }
  teardown { FileUtils.remove_entry(@directory) }

  test "imports one-to-one DM metadata from legacy and encrypted chats without text" do
    import = X::ArchiveImport.import!(archive)
    assert_equal [3, 1], [import.direct_messages_count, import.skipped_count]
    assert_equal %w[incoming outgoing incoming], DirectMessage.order(:occurred_at).pluck(:direction)
    assert_equal ["101"], DirectMessage.distinct.pluck(:partner_x_id)
    assert_equal ["archive"], DirectMessage.distinct.pluck(:source)
    dump = DirectMessage.all.map(&:attributes).to_json
    assert_not_includes dump, "secret"
    assert_not_includes dump, "ENCRYPTED"

    person = Person.resolve_profile!(profile)
    assert person.interactions.awaiting_dm_reply?
    assert_in_delta 200.days.ago.to_i, DirectMessage.covered_since.to_i, 60
  end

  test "re-import adds nothing and another account's archive is refused" do
    X::ArchiveImport.import!(archive)
    assert_equal 0, X::ArchiveImport.import!(archive).direct_messages_count
    error = assert_raises(X::ArchiveImport::Invalid) { X::ArchiveImport.import!(archive(owner: "555")) }
    assert_match "different X account", error.message
    assert_equal 3, DirectMessage.count
  end

  test "a partial archive does not claim coverage" do
    X::ArchiveImport.import!(archive(partial: true))
    assert_nil DirectMessage.covered_since
    assert_equal 3, DirectMessage.count
  end

  test "malformed archives roll back and are handled" do
    path = archive(files: { "data/message-event.js" => [{ "messageEvent" => { "detail" => { "messageCreateEvent" => {} } } }] })
    assert_raises(X::ArchiveImport::Invalid) { X::ArchiveImport.import!(path) }
    assert_equal 0, DirectMessage.count
    File.write(File.join(@directory, "not.zip"), "plain")
    assert_raises(X::ArchiveImport::Invalid) { X::ArchiveImport.import!(File.join(@directory, "not.zip")) }
  end
end
