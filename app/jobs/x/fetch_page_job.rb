# Reads one page of an X collection run outside the web request. Each job is one explicit action in the app:
# the run's reservation, ledger, and page claim still decide whether a paid read happens.
class X::FetchPageJob < ApplicationJob
  queue_as :x_reads
  # One X read at a time per workspace, matching the one-fetching-run rule.
  limits_concurrency to: 1, key: ->(workspace, *) { workspace }, duration: 5.minutes

  # No automatic retries: a retried paid read must be a new decision, not a background loop.
  def perform(workspace, run_id, expected_page)
    Current.set(workspace: workspace) do
      X::SyncRun.find_by(id: run_id)&.fetch_page!(expected_page: expected_page)
    end
  end
end
