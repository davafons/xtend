# Any MCP client can propose now, not only Grok Bot, so research and authorship say "ai" instead of "grok".
class RenameGrokToAI < ActiveRecord::Migration[8.1]
  SOURCES = %w[outreach_candidates drafts draft_alternatives draft_revisions person_tags].freeze

  def change
    rename_table :grok_proposals, :ai_proposals
    rename_column :outreach_candidates, :grok_run_id, :ai_run_id
    reversible do |direction|
      direction.up { relabel "grok", "ai" }
      direction.down { relabel "ai", "grok" }
    end
  end

  private

  def relabel(from, to)
    SOURCES.each { |table| execute "UPDATE #{table} SET source = #{quote(to)} WHERE source = #{quote(from)}" }
  end
end
