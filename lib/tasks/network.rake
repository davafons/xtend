namespace :network do
  desc "Derive the interaction graph from posts and likes saved before the network view existed. Safe to re-run."
  task backfill: :environment do
    Workspace.find_each do |workspace|
      Current.workspace = workspace
      next if workspace.owner_x_id.blank?
      before = X::Interaction.count
      X::SourcePost.where.not(reply_to_x_id: nil).find_each(&:record_reply_interaction)
      Engagement.where(kind: "like").find_each { |engagement| engagement.send(:record_interaction) }
      puts "Workspace #{workspace.id}: #{X::Interaction.count - before} interactions added, #{X::Interaction.count} in total."
    end
  end
end
