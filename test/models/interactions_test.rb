require "test_helper"
require "minitest/mock"
require "tmpdir"

class InteractionsTest < ActiveSupport::TestCase
  def connected(scopes: X::Config::SCOPES)
    Dir.mktmpdir do |directory|
      X::TokenVault.stub(:key_path, Pathname.new(directory).join("key")) do
        connection = X::Connection.connect!({"access_token" => "t", "refresh_token" => "r", "expires_in" => 7200}, {"id" => "999", "username" => "owner"})
        connection.update!(granted_scopes: scopes.join(" "))
        yield connection
      end
    end
  end

  def client_returning(*pages)
    client = Object.new
    queue = pages.dup
    client.define_singleton_method(:page) { |*_, **_| queue.shift }
    client
  end

  def liked(id, author: "101", created_at: 3.days.ago)
    {"id" => id, "author_id" => author, "text" => "Their post", "created_at" => created_at.iso8601, "referenced_posts" => []}
  end

  def dm(id, sender:, conversation: "101-999", created_at: 1.day.ago)
    {"id" => id, "conversation_id" => conversation, "sender_id" => sender, "created_at" => created_at.iso8601}
  end

  def collect(dataset, *pages)
    run = X::SyncRun.start!(dataset: dataset, request_key: SecureRandom.uuid)
    X::Client.stub(:new, client_returning(*pages)) do
      pages.size.times { |page| run.fetch_page!(expected_page: page) }
    end
    run.reload
  end

  def setup_graph(*people)
    snapshot("following", people)
    snapshot("followers", [])
  end

  test "likes attach to the author without a person record and skip your own posts" do
    connected do
      run = collect("liked_posts", {"data" => [liked("1"), liked("2", author: "999")], "meta" => {}, "partial_errors" => false})
      assert_equal "completed", run.status
      assert_equal "backfill", run.mode
      assert_equal ["1"], Engagement.pluck(:post_x_id)
      assert_nil Engagement.first.observed_after
      person = Person.resolve_profile!(profile)
      assert_equal 1, person.engagements.size
    end
  end

  test "a likes refresh stops at saved evidence and records the previous check as a lower bound" do
    connected do
      first = collect("liked_posts", {"data" => [liked("1")], "meta" => {}, "partial_errors" => false})
      refresh = collect("liked_posts", {"data" => [liked("2", created_at: 30.days.ago), liked("1")], "meta" => {"next_token" => "older"}, "partial_errors" => false})
      assert_equal "refresh", refresh.mode
      assert_equal "completed", refresh.status
      fresh = Engagement.find_by!(post_x_id: "2")
      assert_equal first.upper_bound.to_i, fresh.observed_after.to_i
      assert_equal fresh.observed_after, fresh.earliest_at
    end
  end

  test "DM collection keeps one-to-one metadata only and never message text" do
    connected do
      payload = X::Payload.page({"data" => [
        {"id" => "11", "event_type" => "MessageCreate", "text" => "secret words", "dm_conversation_id" => "101-999", "sender_id" => "101", "created_at" => 2.days.ago.iso8601},
        {"id" => "12", "event_type" => "MessageCreate", "text" => "group chat", "dm_conversation_id" => "5555", "sender_id" => "101", "created_at" => 1.day.ago.iso8601}
      ], "meta" => {"result_count" => 2}}, dataset: "dm_events")
      assert_not_includes payload.to_json, "secret words"
      collect("dm_events", payload)
      assert_equal 1, DirectMessage.count
      message = DirectMessage.first
      assert_equal ["101", "incoming"], [message.partner_x_id, message.direction]
      assert_not_includes X::Read.last.payload.to_json, "secret words"

      person = Person.resolve_profile!(profile)
      assert person.interactions.awaiting_dm_reply?
      collect("dm_events", {"data" => [dm("13", sender: "999"), dm("11", sender: "101")], "meta" => {}, "partial_errors" => false})
      assert_not Person.find(person.id).interactions.awaiting_dm_reply?
    end
  end

  test "sources need their read scope before any request" do
    connected(scopes: %w[tweet.read users.read follows.read offline.access]) do
      error = assert_raises(X::Client::Error) { X::SyncRun.start!(dataset: "dm_events", request_key: SecureRandom.uuid) }
      assert_match "dm.read", error.message
    end
  end

  test "likes use owned pricing only with evidence; DMs never do" do
    cycle = X::BillingCycle.current
    cycle.update!(pricing_evidence: "trial", owned_configuration_digest: X::Config.fingerprint)
    assert_equal "owned", cycle.reserve!(dataset: "liked_posts", limit: 100).pricing_basis
    read = cycle.reserve!(dataset: "dm_events", limit: 20)
    assert_equal ["standard", 200_000], [read.pricing_basis, read.reserved_micros]
  end

  test "a recent like, DM, or mention keeps someone out of cleanup" do
    connected do
      liker, messaged, mentioner, quiet = %w[1 2 3 4].map { |id| Person.resolve_profile!(profile(x_id: id, handle: "p#{id}")) }
      setup_graph(liker, messaged, mentioner, quiet)
      collect("liked_posts", {"data" => [liked("50", author: "1", created_at: 2.days.ago), liked("51", author: "4", created_at: 200.days.ago)], "meta" => {}, "partial_errors" => false})
      collect("dm_events", {"data" => [dm("60", sender: "999", conversation: "2-999")], "meta" => {}, "partial_errors" => false})
      mention_run = X::SyncRun.create!(dataset: "mentions", owner_x_id: "999", request_key: SecureRandom.uuid, page_limit: 10, upper_bound: Time.current)
      X::SourcePost.create!(x_id: "70", author_x_id: "3", body: "@owner hi", published_at: 1.day.ago, x_sync_run: mention_run)

      assert_equal [quiet.id], cleanup_ids
      assert_equal "like", Person::Interactions.for(quiet).latest.channel
      assert_equal "mention", Person::Interactions.for(mentioner).latest.channel
    end
  end

  test "DM coverage is continuous only while checks are under 30 days apart" do
    connected do
      [70, 50, 25].each do |days|
        X::SyncRun.create!(dataset: "dm_events", owner_x_id: "999", request_key: SecureRandom.uuid, page_limit: 20,
          upper_bound: days.days.ago, status: "completed")
      end
      assert_in_delta 100.days.ago.to_i, DirectMessage.covered_since.to_i, 5
      X::SyncRun.where(dataset: "dm_events").order(:upper_bound).last.update!(upper_bound: 1.day.ago)
      X::SyncRun.where(dataset: "dm_events").order(:upper_bound).second.update!(upper_bound: 65.days.ago)
      assert_in_delta 31.days.ago.to_i, DirectMessage.covered_since.to_i, 5
    end
  end

  test "timeline shows DM days and likes without message text" do
    connected do
      person = Person.resolve_profile!(profile)
      collect("dm_events", {"data" => [dm("81", sender: "101"), dm("80", sender: "999", created_at: 1.day.ago - 1.minute)], "meta" => {}, "partial_errors" => false})
      collect("liked_posts", {"data" => [liked("90")], "meta" => {}, "partial_errors" => false})
      titles = Person.find(person.id).timeline.map(&:title)
      assert_includes titles, "Direct messages | 1 from you, 1 from them"
      assert_includes titles, "You liked their post"
    end
  end
end
