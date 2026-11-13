require "test_helper"
require "minitest/mock"
require "tmpdir"

class XCollectionTest < ActiveSupport::TestCase
  def connected
    Dir.mktmpdir do |directory|
      X::TokenVault.stub(:key_path, Pathname.new(directory).join("key")) do
        connection = X::Connection.connect!({"access_token" => "test-token", "refresh_token" => "test-refresh", "expires_in" => 7200}, {"id" => "999", "username" => "owner"})
        yield connection
      end
    end
  end

  def page(rows, cursor: nil, partial_errors: false)
    {"data" => rows, "meta" => cursor ? {"next_token" => cursor} : {}, "partial_errors" => partial_errors}
  end

  def raw_profile(id = "101", handle = "builder")
    {"id" => id, "username" => handle, "name" => "A Builder", "description" => "Ships useful things"}
  end

  def source_post(id:, author: "999", parent: nil, to: nil)
    {"id" => id, "author_id" => author, "text" => "A thoughtful post", "created_at" => 5.minutes.ago.iso8601,
      "lang" => "en", "in_reply_to_user_id" => to,
      "referenced_posts" => parent ? [{"id" => parent, "type" => "replied_to"}] : []}.compact
  end

  def start(dataset = "followers", **options)
    X::SyncRun.start!(dataset: dataset, request_key: SecureRandom.uuid, **options)
  end

  test "bulk page sizes are bounded by the X endpoint maximum" do
    connected do
      assert_equal 1000, start("following", page_size: 5000).page_limit
      assert_equal 100, start("own_posts", page_size: 500).page_limit
      assert_raises(ArgumentError) { start("search", page_size: 100) }
    end
  end

  test "insufficient budget blocks a request before dispatch" do
    Current.workspace.update!(monthly_budget_cents: 50)
    connected do
      run = start
      X::Client.stub(:new, -> { flunk "No network client should be constructed" }) { assert_not run.fetch_page!(expected_page: 0) }
      assert_equal "paused", run.reload.status
      assert_equal 0, X::Read.count
      assert_empty Person.all
    end
  end

  test "resource reservations enforce both the trial and provider baseline" do
    cycle = X::BillingCycle.current
    cycle.update!(provider_spend_micros: 9_500_000)
    assert_raises(X::BillingCycle::LimitExceeded) { cycle.reserve!(dataset: "followers", limit: 100) }
    cycle.update!(provider_spend_micros: 0)
    5.times { cycle.reserve!(dataset: "followers", limit: 100) }
    assert_equal 0, X::BillingCycle.trial_remaining_micros
    assert_raises(X::BillingCycle::LimitExceeded) { cycle.reserve!(dataset: "own_posts", limit: 10) }
  end

  test "a failed network request keeps its full reservation" do
    connected do
      run = start
      client = Object.new
      client.define_singleton_method(:page) { |*args, **kwargs| raise X::Client::Error, "The connection to X failed." }
      X::Client.stub(:new, client) { assert_not run.fetch_page!(expected_page: 0) }
      assert_equal "uncertain", X::Read.last.status
      assert_equal 1_000_000, X::BillingCycle.current.pending_micros
      assert_nil run.follow_snapshot.completed_at
      assert_equal 0, run.page_number
    end
  end

  test "pages preserve a partial snapshot and duplicate clicks make no new requests" do
    connected do
      run = start
      calls = 0
      first = page([raw_profile], cursor: "next-page")
      client = Object.new
      client.define_singleton_method(:page) { |*args, **kwargs| calls += 1; first }
      X::Client.stub(:new, client) do
        assert run.fetch_page!(expected_page: 0)
        assert_not run.fetch_page!(expected_page: 0)
      end
      assert_equal 1, calls
      assert_equal "partial", run.reload.status
      assert_nil run.follow_snapshot.completed_at
      assert_equal 10_000, X::BillingCycle.current.pending_micros
      assert_empty cleanup_ids
      second = page([raw_profile("102", "other")])
      client.define_singleton_method(:page) { |*args, **kwargs| second }
      X::Client.stub(:new, client) { assert run.fetch_page!(expected_page: 1) }
      assert_equal "completed", run.reload.status
      assert_equal 2, run.follow_snapshot.people.count
      assert_equal 2, Follow::FollowerPeriod.ongoing.count
      assert_equal 2, X::Read.where(status: "committed").count
    end
  end

  test "saved responses are reapplied without a second network request" do
    connected do
      run = start
      read = X::Read.fetch!(dataset: "followers", limit: 100, run: run) { page([raw_profile]) }
      run.update!(status: "paused")
      X::Client.stub(:new, -> { flunk "Saved response should be reused" }) { assert run.fetch_page!(expected_page: 0) }
      assert_equal "committed", read.reload.status
      assert_equal 1, Person.count
      assert_equal 1, X::Read.count
    end
  end

  test "partial errors never complete an empty follower snapshot" do
    connected do
      run = start
      result = page([], partial_errors: true)
      client = Object.new
      client.define_singleton_method(:page) { |*args, **kwargs| result }
      X::Client.stub(:new, client) { run.fetch_page!(expected_page: 0) }
      assert_nil run.follow_snapshot.reload.completed_at
      assert_empty Follow::FollowerPeriod.all
      assert_equal "paused", run.reload.status
    end
  end

  test "response normalization rejects missing identities and counts" do
    assert_raises(X::Client::Error) { X::Payload.page({"data" => [{"id" => "1"}]}, dataset: "followers") }
    assert_raises(X::Client::Error) { X::Payload.page({}, dataset: "followers") }
    assert_raises(X::Client::Error) { X::Payload.page({"meta" => {}}, dataset: "followers") }
    assert_raises(X::Client::Error) { X::Payload.page({"data" => [], "meta" => {"result_count" => 100}}, dataset: "followers") }
    assert_equal [], X::Payload.page({"meta" => {"result_count" => 0}}, dataset: "followers")["data"]
    assert_raises(X::Client::Error) { X::Payload.page({"data" => [source_post(id: "1").except("author_id")]}, dataset: "mentions") }
  end

  test "historical replies update memory without advancing the daily target" do
    connected do
      Person.resolve_profile!(profile)
      run = start("own_posts")
      X::SourcePost.capture!(source_post(id: "8001", author: "101"), run: run)
      X::SourcePost.capture!(source_post(id: "7001", parent: "8001", to: "101"), run: run)
      X::SourcePost.reconcile_all!
      assert_equal "You replied only", Person.first.reply_state
      assert_equal 0, DailySession.current.progress
      assert_equal "initial", ReplyEvent.first.classification
      assert_equal false, ReplyEvent.first.outreach_eligible
    end
  end

  test "unresolved replies can become initial replies once evidence arrives" do
    connected do
      Person.resolve_profile!(profile)
      start("own_posts")
      travel 20.seconds
      run = start("own_posts", mode: "refresh")
      X::SourcePost.capture!(source_post(id: "7001", parent: "8001", to: "101"), run: run)
      X::SourcePost.reconcile_all!
      assert_equal "unclassified", ReplyEvent.first.classification
      assert_equal 0, DailySession.current.progress
      X::SourcePost.capture!(source_post(id: "8001", author: "101"), run: run)
      X::SourcePost.reconcile_all!
      assert_equal "initial", ReplyEvent.first.reload.classification
      assert_equal 1, DailySession.current.progress
      X::SourcePost.reconcile_all!
      assert_equal 1, DailySession.current.progress
    end
  end

  test "mentions and follow-ups cannot inflate outreach" do
    connected do
      Person.resolve_profile!(profile)
      run = start("mentions", mode: "refresh")
      X::SourcePost.capture!(source_post(id: "8001", author: "101"), run: run)
      X::SourcePost.reconcile_all!
      assert_equal 0, ReplyEvent.count
      X::SourcePost.capture!(source_post(id: "8002", author: "101", parent: "8003", to: "999"), run: run)
      X::SourcePost.capture!(source_post(id: "7001", parent: "8002", to: "101"), run: run)
      X::SourcePost.reconcile_all!
      assert_equal "Two-way", Person.first.reply_state
      assert_equal 0, DailySession.current.progress
      assert_equal "continuation", ReplyEvent.find_by!(x_id: "7001").classification
    end
  end

  test "provider observations do not double-count settled reads or release uncertain reservations" do
    cycle = X::BillingCycle.current
    read = X::Read.fetch!(dataset: "identity", limit: 1) { {"data" => raw_profile} }
    read.mark_applied!
    uncertain = cycle.reserve!(dataset: "followers", limit: 100)
    uncertain.update!(status: "uncertain")
    cycle.observe!(spend_cents: 74)
    assert_equal 1_000_000, cycle.pending_micros
    assert_equal 8_260_000, cycle.remaining_micros
    assert_equal 740_000, cycle.provider_spend_micros
  end

  test "owned pricing needs evidence tied to the current client" do
    cycle = X::BillingCycle.current
    X::Config.stub(:fingerprint, "configuration-a") do
      assert_equal 1_000_000, cycle.reserve!(dataset: "followers", limit: 100).reserved_micros
      cycle.update!(pricing_evidence: "Console owned-read rate checked", owned_configuration_digest: "configuration-a")
      assert_equal 100_000, cycle.reserve!(dataset: "followers", limit: 100).reserved_micros
      assert_equal 10_000, cycle.reserve!(dataset: "identity", limit: 1).reserved_micros
    end
    X::Config.stub(:fingerprint, "configuration-b") { assert_not cycle.owned_pricing? }
  end
  test "a first reply refresh is a baseline and cannot count old posts as fresh outreach" do
    connected do
      run = start("own_posts", mode: "refresh")
      assert_equal "backfill", run.mode
    end
  end


end
