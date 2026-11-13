# Request keys and the one-page-at-a-time rule were unique across the whole app; both belong to a workspace.
class ScopeSyncRunUniquenessToWorkspace < ActiveRecord::Migration[8.1]
  def change
    remove_index :x_sync_runs, :request_key, unique: true, name: "index_x_sync_runs_on_request_key"
    add_index :x_sync_runs, [ :workspace_id, :request_key ], unique: true
    remove_index :x_sync_runs, :owner_x_id, unique: true, where: "status = 'fetching'", name: "one_fetching_run_per_owner"
    add_index :x_sync_runs, :workspace_id, unique: true, where: "status = 'fetching'", name: "one_fetching_run_per_workspace"
    remove_index :x_sync_runs, :workspace_id, name: "index_x_sync_runs_on_workspace_id"
  end
end
