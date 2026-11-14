# Lists of people the owner tends: three relationship tiers (inner circle, circle, getting to know) and any custom
# lists. The "circle" tag the growth plan used becomes the Circle tier.
class CreateLists < ActiveRecord::Migration[8.1]
  TIERS = [
    [ "inner", "Inner circle", 3, 10, 0, "The ten people you most want to be seen by. Turn on X notifications for them and reply early." ],
    [ "circle", "Circle", 7, 50, 1, "Active accounts in your niche you reply to every week, so they keep seeing you." ],
    [ "getting_to_know", "Getting to know", 14, nil, 2, "People you've started talking with. Two-way exchanges here are a sign to move them up." ]
  ].freeze

  def up
    create_table :lists do |t|
      t.integer :workspace_id, null: false
      t.string :name, null: false
      t.string :tier
      t.integer :cadence_days
      t.integer :capacity
      t.text :purpose
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :lists, [ :workspace_id, :name ], unique: true
    add_index :lists, [ :workspace_id, :tier ], unique: true, where: "tier IS NOT NULL"

    create_table :list_memberships do |t|
      t.integer :workspace_id, null: false
      t.integer :list_id, null: false
      t.integer :person_id, null: false
      t.string :source, null: false, default: "owner"
      t.timestamps
    end
    add_index :list_memberships, [ :list_id, :person_id ], unique: true
    add_index :list_memberships, :person_id
    add_index :list_memberships, :workspace_id

    now = connection.quote(Time.current.utc.to_fs(:db))
    select_values("SELECT id FROM workspaces").each do |workspace_id|
      TIERS.each do |tier, name, cadence, capacity, position, purpose|
        execute <<~SQL
          INSERT INTO lists (workspace_id, name, tier, cadence_days, capacity, position, purpose, created_at, updated_at)
          VALUES (#{workspace_id}, #{connection.quote(name)}, #{connection.quote(tier)}, #{cadence}, #{capacity || "NULL"}, #{position}, #{connection.quote(purpose)}, #{now}, #{now})
        SQL
      end
      circle_list = select_value("SELECT id FROM lists WHERE workspace_id = #{workspace_id} AND tier = 'circle'")
      tag = select_value("SELECT id FROM tags WHERE workspace_id = #{workspace_id} AND name = 'circle'")
      next unless tag
      execute <<~SQL
        INSERT INTO list_memberships (workspace_id, list_id, person_id, source, created_at, updated_at)
        SELECT workspace_id, #{circle_list}, person_id, source, created_at, #{now} FROM person_tags WHERE tag_id = #{tag}
      SQL
      execute "DELETE FROM person_tags WHERE tag_id = #{tag}"
      execute "DELETE FROM tags WHERE id = #{tag}"
    end
  end

  def down
    select_values("SELECT id FROM workspaces").each do |workspace_id|
      circle_list = select_value("SELECT id FROM lists WHERE workspace_id = #{workspace_id} AND tier = 'circle'")
      next unless circle_list && select_value("SELECT COUNT(*) FROM list_memberships WHERE list_id = #{circle_list}").to_i.positive?
      now = connection.quote(Time.current.utc.to_fs(:db))
      execute "INSERT INTO tags (workspace_id, name, created_at, updated_at) VALUES (#{workspace_id}, 'circle', #{now}, #{now})"
      tag = select_value("SELECT id FROM tags WHERE workspace_id = #{workspace_id} AND name = 'circle'")
      execute <<~SQL
        INSERT INTO person_tags (workspace_id, person_id, tag_id, source, created_at, updated_at)
        SELECT workspace_id, person_id, #{tag}, source, created_at, #{now} FROM list_memberships WHERE list_id = #{circle_list}
      SQL
    end
    drop_table :list_memberships
    drop_table :lists
  end
end
