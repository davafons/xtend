# There is no signup. The owner allows X accounts here, and they sign in with X.
namespace :users do
  desc "Allow an X account to sign in. HANDLE=... [WORKSPACE_ID=...]. Without WORKSPACE_ID, the first user joins the existing workspace and later users get their own."
  task allow: :environment do
    handle = ENV["HANDLE"].presence || abort("Set HANDLE to an X handle, such as HANDLE=yourhandle.")
    user = User.transaction do
      workspace = if ENV["WORKSPACE_ID"].present?
        Workspace.find(ENV["WORKSPACE_ID"])
      elsif User.none? && Workspace.count == 1
        Workspace.first
      else
        Workspace.create!(name: "@#{handle.delete_prefix("@")}'s workspace")
      end
      workspace.users.create!(x_handle: handle)
    end
    puts "Allowed @#{user.x_handle} in workspace #{user.workspace.id} (#{user.workspace.name}). Their first X sign-in pins the account."
  end

  desc "Remove an X account's access, sign out its sessions, and disconnect the apps it linked. Workspace data stays. HANDLE=..."
  task revoke: :environment do
    user = User.find_by!(x_handle: ENV["HANDLE"].to_s)
    user.destroy!
    puts "Revoked @#{user.x_handle}. Workspace #{user.workspace_id} and its data were kept."
  end

  desc "List the X accounts allowed to sign in"
  task list: :environment do
    User.includes(:workspace).order(:x_handle).each do |user|
      puts "@#{user.x_handle}  #{user.x_user_id ? "pinned to X ID #{user.x_user_id}" : "not signed in yet"}  workspace #{user.workspace_id} (#{user.workspace.name})"
    end
  end
end
