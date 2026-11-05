# Every owner-specific record now belongs to a workspace. Existing rows move to the oldest workspace.
class ScopeDataToWorkspaces < ActiveRecord::Migration[8.1]
  TABLES = %i[
    archive_imports daily_sessions direct_messages discovery_suggestions drafts engagements
    follow_memberships follow_protections follow_reviews follow_snapshots follower_periods grok_proposals
    outreaches people pins post_dispositions posts reply_events reply_reports
    x_authorizations x_billing_cycles x_client_configurations x_connections x_reads x_source_posts x_sync_runs
  ].freeze

  # [table, old index name, new columns, options]
  UNIQUE_INDEXES = [
    [ :daily_sessions, "index_one_active_daily_session", [ :workspace_id ], { where: "completed_at IS NULL", name: "index_one_active_daily_session" } ],
    [ :direct_messages, "index_direct_messages_on_x_id", [ :workspace_id, :x_id ], {} ],
    [ :discovery_suggestions, "index_discovery_suggestions_on_post_x_id", [ :workspace_id, :post_x_id ], {} ],
    [ :drafts, "index_drafts_on_posted_x_id", [ :workspace_id, :posted_x_id ], {} ],
    [ :engagements, "index_engagements_on_kind_and_post_x_id", [ :workspace_id, :kind, :post_x_id ], {} ],
    [ :outreaches, "index_outreaches_on_target_x_id", [ :workspace_id, :target_x_id ], {} ],
    [ :people, "index_people_on_handle", [ :workspace_id, :handle ], {} ],
    [ :people, "index_people_on_x_id", [ :workspace_id, :x_id ], {} ],
    [ :posts, "index_posts_on_x_id", [ :workspace_id, :x_id ], {} ],
    [ :reply_events, "index_reply_events_on_x_id", [ :workspace_id, :x_id ], {} ],
    [ :x_billing_cycles, "index_x_billing_cycles_on_starts_on", [ :workspace_id, :starts_on ], {} ],
    [ :x_client_configurations, "index_single_x_client_configuration", [ :workspace_id ], { name: "index_single_x_client_configuration" } ],
    [ :x_connections, "index_single_owner_x_connection", [ :workspace_id ], { name: "index_single_owner_x_connection" } ],
    [ :x_source_posts, "index_x_source_posts_on_x_id", [ :workspace_id, :x_id ], {} ]
  ].freeze

  def up
    if TABLES.any? { |table| select_value("SELECT 1 FROM #{table} LIMIT 1") } && !select_value("SELECT 1 FROM workspaces LIMIT 1")
      execute "INSERT INTO workspaces (name, created_at, updated_at) VALUES ('Your workspace', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
    end
    workspace_id = select_value("SELECT MIN(id) FROM workspaces")

    TABLES.each do |table|
      add_reference table, :workspace, foreign_key: true, index: true
      execute "UPDATE #{table} SET workspace_id = #{Integer(workspace_id)}" if workspace_id
      change_column_null table, :workspace_id, false
    end

    UNIQUE_INDEXES.each do |table, old_name, columns, options|
      remove_index table, name: old_name
      add_index table, columns, unique: true, **options
    end
    add_index :workspaces, :mcp_token_digest, unique: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
