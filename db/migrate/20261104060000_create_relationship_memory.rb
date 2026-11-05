class CreateRelationshipMemory < ActiveRecord::Migration[8.1]
  def change
    create_table :workspaces do |t|
      t.string :name, default: "Your workspace", null: false
      t.text :builder_interests, default: "AI agents and coding tools\nBuilding and shipping Rails products\nDeveloper workflows\nJapanese learning tools\nLocal-first personal data", null: false
      t.integer :monthly_budget_cents, default: 2500, null: false
      t.timestamps
    end

    create_table :people do |t|
      t.string :x_id
      t.string :handle, null: false
      t.string :name, null: false
      t.text :description
      t.text :notes
      t.timestamps
    end
    add_index :people, :x_id, unique: true
    add_index :people, :handle, unique: true

    create_table :pins do |t|
      t.references :person, null: false, foreign_key: true, index: { unique: true }
      t.timestamps
    end
    create_table :follow_protections do |t|
      t.references :person, null: false, foreign_key: true, index: { unique: true }
      t.timestamps
    end

    create_table :posts do |t|
      t.references :person, null: false, foreign_key: true
      t.string :x_id, null: false
      t.text :body, null: false
      t.string :language, default: "en", null: false
      t.string :topic
      t.text :match_reason
      t.integer :rank, default: 0, null: false
      t.datetime :published_at, null: false
      t.timestamps
    end
    add_index :posts, :x_id, unique: true

    create_table :post_dispositions do |t|
      t.references :post, null: false, foreign_key: true, index: { unique: true }
      t.string :kind, null: false
      t.datetime :until_at
      t.timestamps
    end
    create_table :reply_reports do |t|
      t.references :post, null: false, foreign_key: true, index: { unique: true }
      t.string :reply_url
      t.timestamps
    end

    create_table :reply_events do |t|
      t.references :person, null: false, foreign_key: true
      t.string :x_id, null: false
      t.string :target_x_id, null: false
      t.string :direction, null: false
      t.string :classification, default: "unclassified", null: false
      t.string :source, null: false
      t.datetime :occurred_at, null: false
      t.datetime :confirmed_at, null: false
      t.timestamps
    end
    add_index :reply_events, :x_id, unique: true

    create_table :daily_sessions do |t|
      t.date :anchor_day, null: false
      t.datetime :completed_at
      t.timestamps
    end
    create_table :outreaches do |t|
      t.references :daily_session, foreign_key: true
      t.references :reply_event, null: false, foreign_key: true, index: { unique: true }
      t.string :target_x_id, null: false
      t.timestamps
    end
    add_index :outreaches, :target_x_id, unique: true

    create_table :follow_snapshots do |t|
      t.string :direction, null: false
      t.string :source, null: false
      t.datetime :observed_at, null: false
      t.datetime :completed_at
      t.timestamps
    end
    create_table :follow_memberships do |t|
      t.references :follow_snapshot, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
    end
    add_index :follow_memberships, [ :follow_snapshot_id, :person_id ], unique: true
  end
end
