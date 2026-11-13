namespace :demo do
  desc "Seed fictional data into the isolated XTEND_DEMO=1 database"
  task seed: :environment do
    Current.set(workspace: Workspace.first || Workspace.create!) do
      DemoWorkspace.seed!
      puts "Demo ready: #{Person.count} fictional people, #{Outreach::Candidate.count} tweets. No X requests made."
    end
  end
end
