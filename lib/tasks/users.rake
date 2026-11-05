require "io/console"

# There is no signup page. Accounts are created on the server, and the password is read without echo.
namespace :users do
  def read_password
    return ENV.fetch("PASSWORD") if ENV["PASSWORD"].present?
    abort "Set PASSWORD or run this task in an interactive terminal." unless $stdin.tty?
    print "Password (12 to 72 characters): "
    password = $stdin.noecho(&:gets).to_s.chomp
    print "\nRepeat password: "
    abort "\nThe passwords don't match." unless $stdin.noecho(&:gets).to_s.chomp == password
    puts
    password
  end

  desc "Create a user. EMAIL=... [WORKSPACE_ID=...] [PASSWORD=...]. Without WORKSPACE_ID, the first user joins the existing workspace and later users get their own."
  task create: :environment do
    email = ENV["EMAIL"].presence || abort("Set EMAIL.")
    password = read_password
    user = User.transaction do
      workspace = if ENV["WORKSPACE_ID"].present?
        Workspace.find(ENV["WORKSPACE_ID"])
      elsif User.none? && Workspace.count == 1
        Workspace.first
      else
        Workspace.create!(name: "#{email.split("@").first}'s workspace")
      end
      workspace.users.create!(email_address: email, password: password)
    end
    puts "Created #{user.email_address} in workspace #{user.workspace.id} (#{user.workspace.name})."
  end

  desc "Change a user's password and sign out their other sessions. EMAIL=... [PASSWORD=...]"
  task password: :environment do
    user = User.find_by!(email_address: ENV["EMAIL"].to_s.strip.downcase)
    user.update!(password: read_password)
    user.sessions.destroy_all
    puts "Password changed for #{user.email_address}. Existing sessions were signed out."
  end
end
