class AddPostingNotesToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :posting_notes, :text, default: "", null: false
  end
end
