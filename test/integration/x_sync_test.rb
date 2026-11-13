require "test_helper"
require "minitest/mock"
require "tmpdir"

class XSyncTest < ActionDispatch::IntegrationTest
  test "sample buttons persist one page and repeated form submission cannot refetch it" do
    Dir.mktmpdir do |directory|
      X::TokenVault.stub(:key_path, Pathname.new(directory).join("key")) do
        X::Connection.connect!({"access_token" => "test", "expires_in" => 7200}, {"id" => "999", "username" => "owner"})
        calls = 0
        result = {"data" => [{"id" => "101", "username" => "builder", "name" => "Builder"}], "meta" => {}, "partial_errors" => false}
        client = Object.new
        client.define_singleton_method(:page) { |*args, **kwargs| calls += 1; result }
        key = SecureRandom.uuid
        X::Client.stub(:new, client) do
          assert_enqueued_jobs 1, only: X::FetchPageJob do
            2.times { post x_sync_runs_path, params: {dataset: "followers", request_key: key} }
          end
          assert_equal 0, calls, "the request only queues the read"
          assert_equal "queued", X::SyncRun.last.status
          get x_sources_path
          assert_includes response.body, "Reading from X"
          perform_enqueued_jobs
        end
        assert_equal 1, calls
        assert_equal 1, Person.count
        assert_equal 1, X::SyncRun.count
        assert_equal "completed", X::SyncRun.last.status
        get x_sources_path
        assert_response :success
        assert_includes response.body, "1 account | "
        get follower_history_path
        assert_response :success
        assert_includes response.body, "Current followers | 1"
      end
    end
  end

  test "follower history renders loss windows and post-follow reply timing" do
    person = Person.resolve_profile!(profile)
    [ [[], 20], [[person], 15], [[person], 10], [[], 5] ].each do |people, days|
      Follow::FollowerPeriod.observe!(snapshot("followers", people, observed_at: days.days.ago))
    end
    ingest(occurred_at: 14.days.ago)
    get follower_history_path(view: "lost")
    assert_response :success
    assert_includes response.body, "Lost | 1"
    assert_includes response.body, "#{10.days.ago.strftime('%-d %b')}–#{5.days.ago.strftime('%-d %b %Y')}"
    get follower_history_path(view: "new")
    assert_includes response.body, "1.0–6.0 days"
    assert_includes response.body, "Mean range across 1 completed periods"
    assert_equal 0, X::Read.count
  end

  test "billing observation aligns to provider cycle and never changes the allowance" do
    cycle = X::BillingCycle.current
    post x_billing_cycles_path, params: {cycle: {starts_on: cycle.starts_on.to_s, ends_on: cycle.ends_on.to_s, spend_cents: "73"}}
    assert_redirected_to x_billing_cycles_path
    assert_equal 730_000, cycle.reload.provider_spend_micros
    assert_equal 1000, Current.workspace.monthly_budget_cents
    post x_billing_cycles_path, params: {cycle: {starts_on: cycle.starts_on.to_s, ends_on: cycle.ends_on.to_s, spend_cents: "73.1"}}
    assert_equal 730_000, cycle.reload.provider_spend_micros
  end
  test "a new post read uses a provider-accepted time window without a failed first attempt" do
    Dir.mktmpdir do |directory|
      X::TokenVault.stub(:key_path, Pathname.new(directory).join("key")) do
        X::Connection.connect!({"access_token" => "test", "expires_in" => 7200}, {"id" => "999", "username" => "owner"})
        calls = 0
        http = Object.new
        http.define_singleton_method(:request) do |request|
          calls += 1
          query = URI.decode_www_form(URI.parse(request.path).query).to_h
          accepted = Time.iso8601(query.fetch("end_time")) <= 10.seconds.ago
          klass = accepted ? Net::HTTPOK : Net::HTTPBadRequest
          response = klass.new("1.1", accepted ? "200" : "400", "Test")
          response.body = accepted ? {data: [], meta: {result_count: 0}}.to_json : {detail: "end_time must be at least 10 seconds old"}.to_json
          response.instance_variable_set(:@read, true)
          response
        end
        Net::HTTP.stub(:start, ->(*args, **options, &block) { block.call(http) }) do
          perform_enqueued_jobs do
            post x_sync_runs_path, params: {dataset: "own_posts", request_key: SecureRandom.uuid}
          end
        end
        assert_equal 1, calls
        assert_equal "completed", X::SyncRun.last.status
        assert_equal "committed", X::Read.last.status
        assert_equal 0, X::Read.last.estimated_micros
      end
    end
  end

end
