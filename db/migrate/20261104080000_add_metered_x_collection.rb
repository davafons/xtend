class AddMeteredXCollection < ActiveRecord::Migration[8.1]
  def change
    create_table :x_billing_cycles do |t|
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.bigint :provider_spend_micros, default: 0, null: false
      t.bigint :observed_through_read_id, default: 0, null: false
      t.datetime :observed_at, null: false
      t.string :owned_configuration_digest
      t.text :pricing_evidence
      t.timestamps
    end
    add_index :x_billing_cycles, :starts_on, unique: true
    create_table :x_sync_runs do |t|
      t.string :owner_x_id, null: false
      t.string :dataset, null: false
      t.string :status, default: "ready", null: false
      t.string :mode, default: "backfill", null: false
      t.string :request_key, null: false
      t.string :cursor
      t.string :since_id
      t.datetime :upper_bound, null: false
      t.integer :page_limit, null: false
      t.integer :page_number, default: 0, null: false
      t.integer :resource_count, default: 0, null: false
      t.datetime :finished_at
      t.datetime :retry_at
      t.text :message
      t.references :follow_snapshot, foreign_key: true
      t.json :parameters, default: {}, null: false
      t.timestamps
    end
    add_index :x_sync_runs, :request_key, unique: true
    add_index :x_sync_runs, :owner_x_id, unique: true, where: "status = 'fetching'", name: "one_fetching_run_per_owner"
    create_table :x_reads do |t|
      t.references :x_billing_cycle, null: false, foreign_key: true
      t.references :x_sync_run, foreign_key: true
      t.string :dataset, null: false
      t.string :status, default: "reserved", null: false
      t.string :pricing_basis, null: false
      t.integer :resource_limit, null: false
      t.integer :resource_count
      t.bigint :reserved_micros, null: false
      t.bigint :estimated_micros
      t.boolean :trial, default: true, null: false
      t.json :payload
      t.datetime :dispatched_at
      t.datetime :received_at
      t.datetime :committed_at
      t.text :message
      t.timestamps
    end
    add_column :workspaces, :collection_trial_completed_at, :datetime
    add_column :reply_events, :outreach_eligible, :boolean, default: true, null: false
    create_table :x_source_posts do |t|
      t.string :x_id, null: false
      t.string :author_x_id, null: false
      t.string :parent_x_id
      t.string :reply_to_x_id
      t.string :conversation_x_id
      t.text :body, null: false
      t.string :language
      t.datetime :published_at, null: false
      t.references :x_sync_run, null: false, foreign_key: true
      t.boolean :repost, default: false, null: false
      t.timestamps
    end
    add_index :x_source_posts, :x_id, unique: true
  end
end
