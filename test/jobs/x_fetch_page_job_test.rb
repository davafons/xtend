require "test_helper"
require "minitest/mock"
require "tmpdir"

class XFetchPageJobTest < ActiveJob::TestCase
  def connected
    Dir.mktmpdir do |directory|
      X::TokenVault.stub(:key_path, Pathname.new(directory).join("key")) do
        X::Connection.connect!({ "access_token" => "test-token", "expires_in" => 7200 }, { "id" => "999", "username" => "owner" })
        yield
      end
    end
  end

  def counting_client(rows)
    client = Object.new
    calls = 0
    client.define_singleton_method(:page) { |*args, **kwargs| calls += 1; { "data" => rows, "meta" => {}, "partial_errors" => false } }
    client.define_singleton_method(:calls) { calls }
    client
  end

  test "queued pages are read once by the job, inside the run's workspace" do
    connected do
      run = X::SyncRun.start!(dataset: "followers", request_key: SecureRandom.uuid)
      assert run.enqueue_page!(expected_page: 0)
      assert_not run.enqueue_page!(expected_page: 0), "a second click must not queue another read"
      assert_equal "queued", run.reload.status
      assert_enqueued_jobs 1

      client = counting_client([ { "id" => "101", "username" => "builder", "name" => "Builder" } ])
      workspace = Current.workspace
      Current.reset
      X::Client.stub(:new, client) do
        perform_enqueued_jobs
        X::FetchPageJob.perform_now(workspace, run.id, 0)
      end
      Current.workspace = workspace
      assert_equal 1, client.calls
      assert_equal "completed", run.reload.status
      assert_equal [ "builder" ], Person.pluck(:handle)
    end
  end

  test "a job for another workspace's run does nothing" do
    connected do
      run = X::SyncRun.start!(dataset: "followers", request_key: SecureRandom.uuid)
      run.enqueue_page!(expected_page: 0)
      other = Workspace.create!(name: "Other", owner_x_id: "888")
      X::Client.stub(:new, -> { flunk "No read for a run outside the job's workspace" }) do
        assert_nil X::FetchPageJob.perform_now(other, run.id, 0)
      end
      assert_equal "queued", run.reload.status
    end
  end

  test "only one read is active per owner, and a lost job can be recovered" do
    connected do
      first = X::SyncRun.start!(dataset: "followers", request_key: SecureRandom.uuid)
      second = X::SyncRun.start!(dataset: "following", request_key: SecureRandom.uuid)
      first.enqueue_page!(expected_page: 0)
      assert_raises(X::Client::Error) { second.enqueue_page!(expected_page: 0) }

      assert_raises(X::Client::Error) { first.recover! }
      first.update_column(:updated_at, 3.minutes.ago)
      first.recover!
      assert_equal "paused", first.reload.status
      assert second.enqueue_page!(expected_page: 0)
    end
  end
end
