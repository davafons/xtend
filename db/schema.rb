# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_14_064000) do
  create_table "ai_proposals", force: :cascade do |t|
    t.integer "person_id", null: false
    t.string "kind", null: false
    t.string "status", default: "pending", null: false
    t.json "payload", default: {}, null: false
    t.string "run_id"
    t.string "via", null: false
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["person_id", "kind", "status"], name: "index_ai_proposals_on_person_id_and_kind_and_status"
    t.index ["person_id"], name: "index_ai_proposals_on_person_id"
    t.index ["workspace_id"], name: "index_ai_proposals_on_workspace_id"
  end

  create_table "archive_imports", force: :cascade do |t|
    t.string "owner_x_id", null: false
    t.datetime "generated_at", null: false
    t.datetime "account_created_at", null: false
    t.boolean "partial", default: false, null: false
    t.integer "direct_messages_count", default: 0, null: false
    t.integer "skipped_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["workspace_id"], name: "index_archive_imports_on_workspace_id"
  end

  create_table "direct_messages", force: :cascade do |t|
    t.string "x_id", null: false
    t.string "conversation_x_id", null: false
    t.string "partner_x_id", null: false
    t.string "direction", null: false
    t.datetime "occurred_at", null: false
    t.integer "x_sync_run_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source", default: "x_api", null: false
    t.integer "workspace_id", null: false
    t.index ["partner_x_id", "occurred_at"], name: "index_direct_messages_on_partner_x_id_and_occurred_at"
    t.index ["workspace_id", "x_id"], name: "index_direct_messages_on_workspace_id_and_x_id", unique: true
    t.index ["workspace_id"], name: "index_direct_messages_on_workspace_id"
    t.index ["x_sync_run_id"], name: "index_direct_messages_on_x_sync_run_id"
  end

  create_table "draft_alternatives", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.integer "draft_id", null: false
    t.text "body", null: false
    t.string "source", default: "owner", null: false
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["draft_id"], name: "index_draft_alternatives_on_draft_id"
    t.index ["workspace_id"], name: "index_draft_alternatives_on_workspace_id"
  end

  create_table "draft_revisions", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.integer "draft_id", null: false
    t.text "body", null: false
    t.string "source", default: "owner", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["draft_id"], name: "index_draft_revisions_on_draft_id"
    t.index ["workspace_id"], name: "index_draft_revisions_on_workspace_id"
  end

  create_table "drafts", force: :cascade do |t|
    t.text "body", default: "", null: false
    t.string "status", default: "idea", null: false
    t.string "topic"
    t.text "notes"
    t.string "inspiration_url"
    t.string "posted_x_id"
    t.datetime "posted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.string "source", default: "owner", null: false
    t.index ["status"], name: "index_drafts_on_status"
    t.index ["workspace_id", "posted_x_id"], name: "index_drafts_on_workspace_id_and_posted_x_id", unique: true
    t.index ["workspace_id"], name: "index_drafts_on_workspace_id"
  end

  create_table "engagements", force: :cascade do |t|
    t.string "kind", null: false
    t.string "post_x_id", null: false
    t.string "author_x_id", null: false
    t.text "body"
    t.datetime "post_published_at", null: false
    t.datetime "observed_after"
    t.datetime "observed_at", null: false
    t.integer "x_sync_run_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["author_x_id"], name: "index_engagements_on_author_x_id"
    t.index ["workspace_id", "kind", "post_x_id"], name: "index_engagements_on_workspace_id_and_kind_and_post_x_id", unique: true
    t.index ["workspace_id"], name: "index_engagements_on_workspace_id"
    t.index ["x_sync_run_id"], name: "index_engagements_on_x_sync_run_id"
  end

  create_table "follow_memberships", force: :cascade do |t|
    t.integer "follow_snapshot_id", null: false
    t.integer "person_id", null: false
    t.integer "workspace_id", null: false
    t.index ["follow_snapshot_id", "person_id"], name: "index_follow_memberships_on_follow_snapshot_id_and_person_id", unique: true
    t.index ["follow_snapshot_id"], name: "index_follow_memberships_on_follow_snapshot_id"
    t.index ["person_id"], name: "index_follow_memberships_on_person_id"
    t.index ["workspace_id"], name: "index_follow_memberships_on_workspace_id"
  end

  create_table "follow_protections", force: :cascade do |t|
    t.integer "person_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["person_id"], name: "index_follow_protections_on_person_id", unique: true
    t.index ["workspace_id"], name: "index_follow_protections_on_workspace_id"
  end

  create_table "follow_reviews", force: :cascade do |t|
    t.integer "person_id", null: false
    t.string "decision", null: false
    t.date "reviewed_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["person_id", "reviewed_on"], name: "index_follow_reviews_on_person_id_and_reviewed_on", unique: true
    t.index ["person_id"], name: "index_follow_reviews_on_person_id"
    t.index ["workspace_id"], name: "index_follow_reviews_on_workspace_id"
  end

  create_table "follow_snapshots", force: :cascade do |t|
    t.string "direction", null: false
    t.string "source", null: false
    t.datetime "observed_at", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "follower_tracking_completed_at"
    t.integer "workspace_id", null: false
    t.string "next_cursor"
    t.integer "expected_count"
    t.datetime "last_page_at"
    t.index ["workspace_id"], name: "index_follow_snapshots_on_workspace_id"
  end

  create_table "follower_periods", force: :cascade do |t|
    t.integer "person_id", null: false
    t.integer "first_snapshot_id", null: false
    t.integer "last_snapshot_id", null: false
    t.integer "ended_snapshot_id"
    t.datetime "followed_after"
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "ended_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["ended_snapshot_id"], name: "index_follower_periods_on_ended_snapshot_id"
    t.index ["first_snapshot_id"], name: "index_follower_periods_on_first_snapshot_id"
    t.index ["last_snapshot_id"], name: "index_follower_periods_on_last_snapshot_id"
    t.index ["person_id", "first_snapshot_id"], name: "index_follower_periods_on_person_id_and_first_snapshot_id", unique: true
    t.index ["person_id"], name: "index_follower_periods_on_person_id"
    t.index ["person_id"], name: "one_open_follow_period_per_person", unique: true, where: "ended_by IS NULL"
    t.index ["workspace_id"], name: "index_follower_periods_on_workspace_id"
  end

  create_table "outreach_candidates", force: :cascade do |t|
    t.integer "person_id", null: false
    t.string "x_id", null: false
    t.text "body", null: false
    t.string "language", default: "en", null: false
    t.string "topic"
    t.text "match_reason"
    t.integer "rank", default: 0, null: false
    t.datetime "published_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "reply_count"
    t.string "source", default: "x_api", null: false
    t.string "ai_run_id"
    t.integer "workspace_id", null: false
    t.index ["person_id"], name: "index_outreach_candidates_on_person_id"
    t.index ["workspace_id", "x_id"], name: "index_outreach_candidates_on_workspace_id_and_x_id", unique: true
    t.index ["workspace_id"], name: "index_outreach_candidates_on_workspace_id"
  end

  create_table "outreach_sessions", force: :cascade do |t|
    t.date "anchor_day", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["workspace_id", "anchor_day"], name: "index_outreach_sessions_on_workspace_id_and_anchor_day", unique: true
    t.index ["workspace_id"], name: "index_outreach_sessions_on_workspace_id"
  end

  create_table "outreach_targets", force: :cascade do |t|
    t.integer "outreach_session_id"
    t.integer "reply_event_id", null: false
    t.string "target_x_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["outreach_session_id"], name: "index_outreach_targets_on_outreach_session_id"
    t.index ["reply_event_id"], name: "index_outreach_targets_on_reply_event_id", unique: true
    t.index ["workspace_id", "target_x_id"], name: "index_outreach_targets_on_workspace_id_and_target_x_id", unique: true
    t.index ["workspace_id"], name: "index_outreach_targets_on_workspace_id"
  end

  create_table "people", force: :cascade do |t|
    t.string "x_id"
    t.string "handle", null: false
    t.string "name", null: false
    t.text "description"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "avatar_url"
    t.string "banner_url"
    t.string "location"
    t.string "website_url"
    t.integer "followers_count"
    t.integer "following_count"
    t.integer "posts_count"
    t.datetime "joined_x_at"
    t.datetime "profile_observed_at"
    t.integer "workspace_id", null: false
    t.datetime "last_posted_at"
    t.boolean "you_follow"
    t.datetime "you_follow_seen_at"
    t.boolean "follows_you"
    t.datetime "follows_you_seen_at"
    t.index ["workspace_id", "handle"], name: "index_people_on_workspace_id_and_handle", unique: true
    t.index ["workspace_id", "x_id"], name: "index_people_on_workspace_id_and_x_id", unique: true
    t.index ["workspace_id"], name: "index_people_on_workspace_id"
  end

  create_table "person_tags", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.integer "person_id", null: false
    t.integer "tag_id", null: false
    t.string "source", default: "owner", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id", "tag_id"], name: "index_person_tags_on_person_id_and_tag_id", unique: true
    t.index ["person_id"], name: "index_person_tags_on_person_id"
    t.index ["tag_id"], name: "index_person_tags_on_tag_id"
    t.index ["workspace_id"], name: "index_person_tags_on_workspace_id"
  end

  create_table "pins", force: :cascade do |t|
    t.integer "person_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["person_id"], name: "index_pins_on_person_id", unique: true
    t.index ["workspace_id"], name: "index_pins_on_workspace_id"
  end

  create_table "reply_events", force: :cascade do |t|
    t.integer "person_id", null: false
    t.string "x_id", null: false
    t.string "target_x_id", null: false
    t.string "direction", null: false
    t.string "classification", default: "unclassified", null: false
    t.string "source", null: false
    t.datetime "occurred_at", null: false
    t.datetime "confirmed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "outreach_eligible", default: true, null: false
    t.integer "workspace_id", null: false
    t.datetime "dismissed_at"
    t.index ["person_id"], name: "index_reply_events_on_person_id"
    t.index ["workspace_id", "x_id"], name: "index_reply_events_on_workspace_id_and_x_id", unique: true
    t.index ["workspace_id"], name: "index_reply_events_on_workspace_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "tags", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "name"], name: "index_tags_on_workspace_id_and_name", unique: true
    t.index ["workspace_id"], name: "index_tags_on_workspace_id"
  end

  create_table "users", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "x_handle", null: false
    t.string "x_user_id"
    t.string "theme", default: "dim", null: false
    t.index ["workspace_id"], name: "index_users_on_workspace_id"
    t.index ["x_handle"], name: "index_users_on_x_handle", unique: true
    t.index ["x_user_id"], name: "index_users_on_x_user_id", unique: true
  end

  create_table "workspaces", force: :cascade do |t|
    t.string "name", default: "Your workspace", null: false
    t.text "builder_interests", default: "AI agents and coding tools\nBuilding and shipping Rails products\nDeveloper workflows\nJapanese learning tools\nLocal-first personal data", null: false
    t.integer "monthly_budget_cents", default: 1000, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "owner_x_id"
    t.datetime "collection_trial_completed_at"
    t.string "mcp_token_digest"
    t.datetime "mcp_token_created_at"
    t.datetime "mcp_token_used_at"
    t.boolean "mcp_share_notes", default: false, null: false
    t.boolean "mcp_share_dms", default: false, null: false
    t.string "capture_token_digest"
    t.datetime "capture_token_created_at"
    t.datetime "capture_token_used_at"
    t.text "posting_notes", default: "", null: false
    t.integer "owner_followers_count"
    t.integer "owner_following_count"
    t.datetime "owner_counts_seen_at"
    t.datetime "captured_at"
    t.json "last_capture"
    t.index ["capture_token_digest"], name: "index_workspaces_on_capture_token_digest", unique: true
    t.index ["mcp_token_digest"], name: "index_workspaces_on_mcp_token_digest", unique: true
  end

  create_table "x_accounts", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.string "x_id", null: false
    t.string "handle", null: false
    t.string "name", null: false
    t.text "description"
    t.string "avatar_url"
    t.integer "followers_count"
    t.integer "following_count"
    t.integer "posts_count"
    t.boolean "verified", default: false, null: false
    t.datetime "observed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "handle"], name: "index_x_accounts_on_workspace_id_and_handle"
    t.index ["workspace_id", "x_id"], name: "index_x_accounts_on_workspace_id_and_x_id", unique: true
    t.index ["workspace_id"], name: "index_x_accounts_on_workspace_id"
  end

  create_table "x_billing_cycles", force: :cascade do |t|
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.bigint "provider_spend_micros", default: 0, null: false
    t.bigint "observed_through_read_id", default: 0, null: false
    t.datetime "observed_at", null: false
    t.string "owned_configuration_digest"
    t.text "pricing_evidence"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["workspace_id", "starts_on"], name: "index_x_billing_cycles_on_workspace_id_and_starts_on", unique: true
    t.index ["workspace_id"], name: "index_x_billing_cycles_on_workspace_id"
  end

  create_table "x_connections", force: :cascade do |t|
    t.string "x_user_id", null: false
    t.string "username", null: false
    t.text "token_ciphertext", null: false
    t.text "granted_scopes", null: false
    t.datetime "expires_at", null: false
    t.datetime "identity_checked_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.string "avatar_url"
    t.index ["workspace_id"], name: "index_single_owner_x_connection", unique: true
    t.index ["workspace_id"], name: "index_x_connections_on_workspace_id"
  end

  create_table "x_follows", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.string "follower_x_id", null: false
    t.string "followed_x_id", null: false
    t.string "seen_on", null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "followed_at"
    t.index ["workspace_id", "followed_x_id"], name: "index_x_follows_on_workspace_id_and_followed_x_id"
    t.index ["workspace_id", "follower_x_id", "followed_x_id"], name: "idx_on_workspace_id_follower_x_id_followed_x_id_dc37aec6a3", unique: true
    t.index ["workspace_id"], name: "index_x_follows_on_workspace_id"
  end

  create_table "x_interactions", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.string "kind", null: false
    t.string "source_x_id", null: false
    t.string "target_x_id", null: false
    t.string "post_x_id", null: false
    t.string "target_post_x_id"
    t.datetime "occurred_at"
    t.datetime "observed_at", null: false
    t.index ["workspace_id", "kind", "post_x_id", "source_x_id", "target_x_id"], name: "index_x_interactions_uniqueness", unique: true
    t.index ["workspace_id", "source_x_id", "target_x_id"], name: "idx_on_workspace_id_source_x_id_target_x_id_0c6ec163ad"
    t.index ["workspace_id", "target_x_id"], name: "index_x_interactions_on_workspace_id_and_target_x_id"
    t.index ["workspace_id"], name: "index_x_interactions_on_workspace_id"
  end

  create_table "x_post_observations", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.string "post_x_id", null: false
    t.string "surface", null: false
    t.datetime "observed_at", null: false
    t.integer "reply_count"
    t.integer "like_count"
    t.integer "repost_count"
    t.integer "quote_count"
    t.integer "bookmark_count"
    t.integer "view_count"
    t.index ["workspace_id", "post_x_id", "observed_at"], name: "idx_on_workspace_id_post_x_id_observed_at_44a23d0951"
    t.index ["workspace_id", "surface", "observed_at"], name: "idx_on_workspace_id_surface_observed_at_c1edbcccd3"
    t.index ["workspace_id"], name: "index_x_post_observations_on_workspace_id"
  end

  create_table "x_reads", force: :cascade do |t|
    t.integer "x_billing_cycle_id", null: false
    t.integer "x_sync_run_id"
    t.string "dataset", null: false
    t.string "status", default: "reserved", null: false
    t.string "pricing_basis", null: false
    t.integer "resource_limit", null: false
    t.integer "resource_count"
    t.bigint "reserved_micros", null: false
    t.bigint "estimated_micros"
    t.boolean "trial", default: true, null: false
    t.json "payload"
    t.datetime "dispatched_at"
    t.datetime "received_at"
    t.datetime "committed_at"
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["workspace_id"], name: "index_x_reads_on_workspace_id"
    t.index ["x_billing_cycle_id"], name: "index_x_reads_on_x_billing_cycle_id"
    t.index ["x_sync_run_id"], name: "index_x_reads_on_x_sync_run_id"
  end

  create_table "x_source_posts", force: :cascade do |t|
    t.string "x_id", null: false
    t.string "author_x_id", null: false
    t.string "parent_x_id"
    t.string "reply_to_x_id"
    t.string "conversation_x_id"
    t.text "body", null: false
    t.string "language"
    t.datetime "published_at", null: false
    t.integer "x_sync_run_id", null: false
    t.boolean "repost", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "reply_count"
    t.integer "workspace_id", null: false
    t.string "quoted_x_id"
    t.string "reposted_x_id"
    t.integer "like_count"
    t.integer "repost_count"
    t.integer "quote_count"
    t.integer "bookmark_count"
    t.integer "view_count"
    t.string "media_kinds"
    t.boolean "has_link", default: false, null: false
    t.datetime "metrics_observed_at"
    t.datetime "first_seen_at"
    t.index ["workspace_id", "author_x_id", "published_at"], name: "idx_on_workspace_id_author_x_id_published_at_8e405ab74e"
    t.index ["workspace_id", "published_at"], name: "index_x_source_posts_on_workspace_id_and_published_at"
    t.index ["workspace_id", "quoted_x_id"], name: "index_x_source_posts_on_workspace_id_and_quoted_x_id"
    t.index ["workspace_id", "reply_to_x_id"], name: "index_x_source_posts_on_workspace_id_and_reply_to_x_id"
    t.index ["workspace_id", "x_id"], name: "index_x_source_posts_on_workspace_id_and_x_id", unique: true
    t.index ["workspace_id"], name: "index_x_source_posts_on_workspace_id"
    t.index ["x_sync_run_id"], name: "index_x_source_posts_on_x_sync_run_id"
  end

  create_table "x_sync_runs", force: :cascade do |t|
    t.string "owner_x_id", null: false
    t.string "dataset", null: false
    t.string "status", default: "ready", null: false
    t.string "mode", default: "backfill", null: false
    t.string "request_key", null: false
    t.string "cursor"
    t.string "since_id"
    t.datetime "upper_bound", null: false
    t.integer "page_limit", null: false
    t.integer "page_number", default: 0, null: false
    t.integer "resource_count", default: 0, null: false
    t.datetime "finished_at"
    t.datetime "retry_at"
    t.text "message"
    t.integer "follow_snapshot_id"
    t.json "parameters", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["follow_snapshot_id"], name: "index_x_sync_runs_on_follow_snapshot_id"
    t.index ["owner_x_id"], name: "one_fetching_run_per_owner", unique: true, where: "status = 'fetching'"
    t.index ["request_key"], name: "index_x_sync_runs_on_request_key", unique: true
    t.index ["workspace_id"], name: "index_x_sync_runs_on_workspace_id"
  end

  add_foreign_key "ai_proposals", "people"
  add_foreign_key "ai_proposals", "workspaces"
  add_foreign_key "archive_imports", "workspaces"
  add_foreign_key "direct_messages", "workspaces"
  add_foreign_key "direct_messages", "x_sync_runs"
  add_foreign_key "draft_alternatives", "drafts"
  add_foreign_key "draft_alternatives", "workspaces"
  add_foreign_key "draft_revisions", "drafts"
  add_foreign_key "draft_revisions", "workspaces"
  add_foreign_key "drafts", "workspaces"
  add_foreign_key "engagements", "workspaces"
  add_foreign_key "engagements", "x_sync_runs"
  add_foreign_key "follow_memberships", "follow_snapshots"
  add_foreign_key "follow_memberships", "people"
  add_foreign_key "follow_memberships", "workspaces"
  add_foreign_key "follow_protections", "people"
  add_foreign_key "follow_protections", "workspaces"
  add_foreign_key "follow_reviews", "people"
  add_foreign_key "follow_reviews", "workspaces"
  add_foreign_key "follow_snapshots", "workspaces"
  add_foreign_key "follower_periods", "follow_snapshots", column: "ended_snapshot_id"
  add_foreign_key "follower_periods", "follow_snapshots", column: "first_snapshot_id"
  add_foreign_key "follower_periods", "follow_snapshots", column: "last_snapshot_id"
  add_foreign_key "follower_periods", "people"
  add_foreign_key "follower_periods", "workspaces"
  add_foreign_key "outreach_candidates", "people"
  add_foreign_key "outreach_candidates", "workspaces"
  add_foreign_key "outreach_sessions", "workspaces"
  add_foreign_key "outreach_targets", "outreach_sessions"
  add_foreign_key "outreach_targets", "reply_events"
  add_foreign_key "outreach_targets", "workspaces"
  add_foreign_key "people", "workspaces"
  add_foreign_key "person_tags", "people"
  add_foreign_key "person_tags", "tags"
  add_foreign_key "person_tags", "workspaces"
  add_foreign_key "pins", "people"
  add_foreign_key "pins", "workspaces"
  add_foreign_key "reply_events", "people"
  add_foreign_key "reply_events", "workspaces"
  add_foreign_key "sessions", "users"
  add_foreign_key "tags", "workspaces"
  add_foreign_key "users", "workspaces"
  add_foreign_key "x_accounts", "workspaces"
  add_foreign_key "x_billing_cycles", "workspaces"
  add_foreign_key "x_connections", "workspaces"
  add_foreign_key "x_follows", "workspaces"
  add_foreign_key "x_interactions", "workspaces"
  add_foreign_key "x_post_observations", "workspaces"
  add_foreign_key "x_reads", "workspaces"
  add_foreign_key "x_reads", "x_billing_cycles"
  add_foreign_key "x_reads", "x_sync_runs"
  add_foreign_key "x_source_posts", "workspaces"
  add_foreign_key "x_source_posts", "x_sync_runs"
  add_foreign_key "x_sync_runs", "follow_snapshots"
  add_foreign_key "x_sync_runs", "workspaces"
end
