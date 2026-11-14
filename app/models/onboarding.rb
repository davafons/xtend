# The Get started checklist for a new workspace. Each step is done when Xtend sees its evidence, never by a tick:
# an archive imported, the extension connected, complete follow lists, X analytics collected, an AI connected, a
# growth plan started. Every step is optional; the first four are what make Xtend useful.
class Onboarding
  Step = Data.define(:key, :title, :why, :done, :required)

  def initialize(workspace = Current.workspace)
    @workspace = workspace
  end

  def steps
    @steps ||= [
      Step.new(:archive, "Import your X archive",
        "Your posts and replies become people and full reply history at once, and DMs add who and when.", X::ArchiveImport.where(status: "completed").exists?, true),
      Step.new(:extension, "Install the browser extension",
        "It saves what x.com already loads while you browse, for free, and shows what Xtend knows beside people's names.", grant?("capture"), true),
      Step.new(:follow_lists, "Complete your follow lists",
        "Scroll your own Followers and Following pages on x.com to the end. That's a free, complete follow check.", Follow::Graph.latest.complete?, true),
      Step.new(:analytics, "Open X Analytics once",
        "Saves your impressions, profile visits, and busy hours, which Outreach and Growth use.", X::Analytics.last_collected_at.present?, true),
      Step.new(:ai, "Connect an AI",
        "Any MCP client can tag people, review follows, and write your weekly review.", grant?("mcp"), false),
      Step.new(:growth, "Start a growth plan",
        "A follower goal with weekly checkpoints and a circle of people to reply to.", @workspace.growth_started_on.present?, false)
    ]
  end

  def essentials = steps.select(&:required)
  def finished? = essentials.all?(&:done)
  def remaining = essentials.count { !_1.done }

  private

  def grant?(scope) = @workspace.oauth_grants.active.where(scope: scope).exists?
end
