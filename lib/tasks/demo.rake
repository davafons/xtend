namespace :demo do
  desc "Seed fictional data into the isolated CRM_DEMO=1 database"
  task seed: :environment do
    Current.set(workspace: Workspace.first || Workspace.create!) do
      DemoWorkspace.seed!
      puts "Demo ready: #{Person.count} fictional people, #{Post.count} tweets. No X requests made."
    end
  end
end
