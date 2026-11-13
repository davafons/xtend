# X::FollowEdge and X::ArchiveImport now read tables named like the rest of the X namespace.
class NameTablesAfterTheirModels < ActiveRecord::Migration[8.1]
  def change
    rename_table :x_follows, :x_follow_edges
    rename_table :archive_imports, :x_archive_imports
  end
end
