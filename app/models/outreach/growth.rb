# The growth plan: from your follower count when you started to a goal over WEEKS weeks, the reply-first way that
# works below 1,000 followers. Replies to a circle of accounts in your niche, answering everyone who replies, one
# post a day with a story or a build update twice a week, and a weekly look at X analytics.
#
# Each week has follower and profile-visit checkpoints and a checklist. Xtend ticks what it can see (replies, replies
# to your circle, your posts, X analytics opened, circle people pinned); you tick the rest. Followers come from the
# newest count Xtend has by each week's end (X's own count on your profile, X analytics, or a complete follower
# check), and visits from X analytics, so a week without them shows as missing, not zero.
class Outreach::Growth
  WEEKS = 16
  DEFAULT_GOAL = 1_000
  CIRCLE_TAG = "circle"
  CIRCLE_PINS = 10
  # Share of the way from start to goal by the end of a week: slow at first, faster as replies compound.
  CURVE = { 0 => 0.0, 1 => 0.012, 2 => 0.036, 4 => 0.108, 8 => 0.337, 12 => 0.639, 16 => 1.0 }.freeze
  # Profile visits to aim for in a week, from X analytics.
  VISITS = { 0 => 5, 1 => 15, 2 => 25, 4 => 40, 8 => 70, 12 => 100, 16 => 130 }.freeze
  # The weeks to stop and judge, as the guide says: not every morning.
  REVIEWS = { 4 => "First review: under the line, change who you reply to and how before adding volume.",
    8 => "Main review: keep what brought profile visits, drop the rest." }.freeze
  REPLIES = 100
  CIRCLE_SHARE = 0.6
  POSTS = 5

  # key => [label, why, :auto or :manual]
  SETUP = {
    "profile" => [ "Your bio says what you build and for whom", "Your profile is the landing page every good reply sends people to.", :manual ],
    "pinned_post" => [ "A story post pinned on your profile", "Visitors decide in seconds; a story with a number tells them why to follow.", :manual ],
    "pins" => [ "Your top #{CIRCLE_PINS} circle people pinned in Xtend", "Their fresh posts then lead Outreach's Reply now.", :auto ],
    "notifications" => [ "X notifications on for those #{CIRCLE_PINS}", "Replies in a post's first hour are the ones that get seen.", :manual ]
  }.freeze
  WEEKLY = {
    "replies" => [ "#{REPLIES} replies (#{Outreach::Session::TARGET} a day, five days)", "Below 1,000 followers, replies are most of the work.", :auto ],
    "circle" => [ "#{(CIRCLE_SHARE * 100).round}% of them to your circle", "Being seen again and again by the same people is what turns replies into follows.", :auto ],
    "posts" => [ "#{POSTS} posts of your own", "A daily post gives the people your replies send over something to follow.", :auto ],
    "story" => [ "One story post", "The failures post, the bet, the journey with a number, or the transformation. Your marathon post was the one that brought follows.", :manual ],
    "build" => [ "One post about what you're building", "The daily update: what you shipped, with a screenshot or a number.", :manual ],
    "answered" => [ "Every reply to you answered", "Conversations under your own posts are what the ranker rewards most.", :manual ],
    "analytics" => [ "X Analytics opened (Overview, Content, Audience)", "Keeps busy hours and what paid off current.", :auto ],
    "review" => [ "Weekly review done", "Ask your AI to run the Xtend task weekly_review, then decide what to change.", :manual ]
  }.freeze

  Week = Data.define(:number, :starts_on, :ends_on, :followers, :followers_target, :visits, :visits_target, :analytics_days) do
    def range = starts_on.beginning_of_day..ends_on.end_of_day
  end

  attr_reader :workspace

  def initialize(workspace = Current.workspace, today: Date.current)
    @workspace = workspace
    @today = today
  end

  def started? = workspace.growth_started_on.present?
  def goal = workspace.growth_goal || DEFAULT_GOAL
  def started_on = workspace.growth_started_on
  def start_followers = workspace.growth_start_followers || followers || 0

  # The plan week today falls in: 0 before it starts, past WEEKS after it ends.
  def current_week
    return 0 unless started? && @today >= started_on
    (@today - started_on).to_i / 7 + 1
  end

  def week(number)
    from = started_on + (number - 1).weeks
    to = from + 6.days
    days = X::AccountDay.between(from, to).to_a
    Week.new(number, from, to, followers_at([ to.end_of_day, Time.current ].min), followers_target(number),
      (days.sum { _1.count(:profile_visits) } if days.any?), target(VISITS, number), days.size)
  end

  def weeks = (1..WEEKS).map { week(_1) }

  def followers_target(number)
    (start_followers + (goal - start_followers) * target(CURVE, number)).round(-1).clamp(start_followers, goal)
  end

  # The newest follower count Xtend has: [count, at, source].
  def latest_followers
    @latest_followers ||= follower_points.max_by { _2 }
  end

  def followers = latest_followers&.first

  def followers_at(time)
    follower_points.select { |_, at| at <= time }.max_by { _2 }&.first
  end

  # Whether you're at or above the line for the week: nil when the count is unknown.
  def on_track?(week) = week.followers && week.followers >= week.followers_target

  # What Xtend sees for a week's automatic items: { key => [done?, detail] }.
  def automatic(number)
    range = week_range(number)
    replies = ReplyEvent.where(direction: "outgoing", occurred_at: range)
    total = replies.count
    to_circle = replies.where(person_id: circle.select(:id)).count
    posts = own_posts(range)
    opened = analytics_opened?(range)
    pinned = circle.where(id: Pin.select(:person_id)).count
    {
      "replies" => [ total >= REPLIES, "#{total} of #{REPLIES}" ],
      "circle" => [ total.positive? && to_circle >= total * CIRCLE_SHARE, total.positive? ? "#{to_circle} of #{total} (#{(to_circle * 100.0 / total).round}%)" : "No replies yet" ],
      "posts" => [ posts >= POSTS, "#{posts} of #{POSTS}" ],
      "analytics" => [ opened, opened ? "Collected this week" : "Not this week" ],
      "pins" => [ pinned >= CIRCLE_PINS, "#{pinned} of #{CIRCLE_PINS} pinned" ]
    }
  end

  def checked(number) = Outreach::GrowthCheck.where(week: number).pluck(:key).to_set

  # The checklist for a week: [[key, label, why, kind, done?, detail]], setup items first in week 1.
  def checklist(number)
    auto = automatic(number)
    ticks = checked(number)
    items = (number == 1 ? SETUP : {}).merge(WEEKLY)
    items.map do |key, (label, why, kind)|
      done, detail = kind == :auto ? auto.fetch(key) : [ ticks.include?(key), nil ]
      [ key, label, why, kind, done, detail ]
    end
  end

  # Your circle, people you haven't replied to this week first, each with their freshest post you haven't answered.
  CircleMember = Data.define(:person, :replied_this_week, :last_reply_at, :fresh_post)

  def circle_members(number = [ current_week, 1 ].max)
    range = week_range(number)
    people = circle.includes(:pin, :tags).to_a
    replied = ReplyEvent.where(direction: "outgoing", person_id: people.map(&:id), occurred_at: range).distinct.pluck(:person_id).to_set
    last = ReplyEvent.where(direction: "outgoing", person_id: people.map(&:id)).group(:person_id).maximum(:occurred_at)
    answered = ReplyEvent.where(direction: "outgoing").select(:target_x_id)
    fresh = X::SourcePost.where(author_x_id: people.map(&:x_id).compact, repost: false, reply_to_x_id: nil, published_at: 48.hours.ago..)
      .where.not(x_id: answered).order(published_at: :desc).group_by(&:author_x_id).transform_values(&:first)
    people.map { CircleMember.new(_1, replied.include?(_1.id), last[_1.id], fresh[_1.x_id]) }
      .sort_by { [ _1.replied_this_week ? 1 : 0, _1.fresh_post ? 0 : 1, _1.person.pin ? 0 : 1, _1.person.name.downcase ] }
  end

  def circle = Person.tagged(CIRCLE_TAG)

  private

  def week_range(number)
    from = started_on + (number - 1).weeks
    from.beginning_of_day..(from + 6.days).end_of_day
  end

  # A value on a curve given at some weeks, straight between them.
  def target(curve, number)
    return curve[number] if curve.key?(number)
    low = curve.keys.select { _1 < number }.max || curve.keys.min
    high = curve.keys.select { _1 > number }.min || curve.keys.max
    return curve[high] if low == high
    value = curve[low] + (curve[high] - curve[low]) * (number - low).fdiv(high - low)
    curve.equal?(VISITS) ? value.round : value
  end

  def follower_points
    @follower_points ||= begin
      points = []
      points << [ workspace.owner_followers_count, workspace.owner_counts_seen_at, "your profile" ] if workspace.owner_followers_count && workspace.owner_counts_seen_at
      X::AnalyticsSnapshot.where(kind: "account").find_each do |snapshot|
        points << [ snapshot.data["followers"], snapshot.observed_at, "X analytics" ] if snapshot.data["followers"]
      end
      Follow::Snapshot.where(direction: "followers").where.not(completed_at: nil).find_each do |snapshot|
        points << [ snapshot.follow_memberships.count, snapshot.observed_at, "complete follower check" ]
      end
      points
    end
  end

  def own_posts(range)
    owner = workspace.owner_x_id
    return 0 if owner.blank?
    X::SourcePost.where(author_x_id: owner, repost: false, reply_to_x_id: nil, published_at: range).count
  end

  def analytics_opened?(range)
    [ X::AccountDay, X::PostAnalytic, X::AnalyticsHour ].any? { _1.where(observed_at: range).exists? }
  end
end
