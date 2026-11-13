class AddLastCaptureToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :captured_at, :datetime
    add_column :workspaces, :last_capture, :json
  end
end
