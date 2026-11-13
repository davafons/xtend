# Drops single-column indexes that a composite index starting with the same column already covers, and adds the
# workspace-scoped indexes that queries filter on: replies and conversations under a post, targets already
# replied to, DM partners, liked authors, and drafts by status.
class TidyIndexes < ActiveRecord::Migration[8.1]
  COVERED_WORKSPACE_INDEXES = %i[
    direct_messages drafts engagements outreach_candidates outreach_sessions outreach_targets people reply_events
    tags x_accounts x_billing_cycles x_connections x_follows x_interactions x_post_observations x_source_posts
  ].freeze
  COVERED_PERSON_INDEXES = %i[ai_proposals follow_reviews follower_periods person_tags].freeze

  def change
    COVERED_WORKSPACE_INDEXES.each { |table| remove_index table, :workspace_id, name: "index_#{table}_on_workspace_id" }
    COVERED_PERSON_INDEXES.each { |table| remove_index table, :person_id, name: "index_#{table}_on_person_id" }
    remove_index :follow_memberships, :follow_snapshot_id, name: "index_follow_memberships_on_follow_snapshot_id"

    remove_index :direct_messages, [ :partner_x_id, :occurred_at ], name: "index_direct_messages_on_partner_x_id_and_occurred_at"
    add_index :direct_messages, [ :workspace_id, :partner_x_id, :occurred_at ]
    remove_index :engagements, :author_x_id, name: "index_engagements_on_author_x_id"
    add_index :engagements, [ :workspace_id, :author_x_id ]
    remove_index :drafts, :status, name: "index_drafts_on_status"
    add_index :drafts, [ :workspace_id, :status ]

    add_index :x_source_posts, [ :workspace_id, :parent_x_id ]
    add_index :x_source_posts, [ :workspace_id, :conversation_x_id ]
    add_index :reply_events, [ :workspace_id, :target_x_id ]
    add_index :reply_events, [ :workspace_id, :direction, :occurred_at ]
  end
end
