# A draft keeps one main text in drafts.body. Alternatives are other versions of the same idea (yours or Grok's),
# and revisions are the main text's history, so a change or a swap can be undone.
class CreateDraftAlternativesAndRevisions < ActiveRecord::Migration[8.1]
  def change
    add_column :drafts, :source, :string, null: false, default: "owner"

    create_table :draft_alternatives do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :draft, null: false, foreign_key: true
      t.text :body, null: false
      t.string :source, null: false, default: "owner"
      t.string :note
      t.timestamps
    end

    create_table :draft_revisions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :draft, null: false, foreign_key: true
      t.text :body, null: false
      t.string :source, null: false, default: "owner"
      t.timestamps
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO draft_revisions (workspace_id, draft_id, body, source, created_at, updated_at)
          SELECT workspace_id, id, body, 'owner', updated_at, updated_at FROM drafts WHERE body <> ''
        SQL
      end
    end
  end
end
