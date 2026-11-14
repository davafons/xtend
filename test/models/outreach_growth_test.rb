require "test_helper"

class OutreachGrowthTest < ActiveSupport::TestCase
  setup do
    Current.workspace.update!(growth_goal: 1000, growth_started_on: Date.new(2026, 11, 2), growth_start_followers: 170)
  end

  test "checkpoints climb slowly then faster, from the start count to the goal" do
    growth = Outreach::Growth.new(today: Date.new(2026, 11, 14))
    assert_equal 2, growth.current_week
    assert_equal 170, growth.followers_target(0)
    assert_equal [ 180, 200, 260, 450, 700, 1000 ], [ 1, 2, 4, 8, 12, 16 ].map { growth.followers_target(_1) }
    assert_operator growth.followers_target(6), :>, growth.followers_target(5)
    assert_equal 0, Outreach::Growth.new(today: Date.new(2026, 11, 1)).current_week
  end

  test "followers are the newest count by each week's end, and a week without one is unknown" do
    Current.workspace.update!(owner_followers_count: 205, owner_counts_seen_at: Time.zone.local(2026, 11, 12, 10))
    X::AnalyticsSnapshot.record!("account", Date.new(2026, 11, 4), Date.new(2026, 11, 4), { "followers" => 175 }, at: Time.zone.local(2026, 11, 4, 9))
    growth = Outreach::Growth.new(today: Date.new(2026, 11, 14))
    travel_to Time.zone.local(2026, 11, 14, 12) do
      assert_equal 175, growth.week(1).followers
      assert_not growth.on_track?(growth.week(1))
      assert_equal 205, growth.week(2).followers
      assert growth.on_track?(growth.week(2))
      assert_equal [ 205, Time.zone.local(2026, 11, 12, 10), "your profile" ], growth.latest_followers
    end
    Current.workspace.update!(owner_followers_count: nil, owner_counts_seen_at: nil)
    X::AnalyticsSnapshot.delete_all
    assert_nil Outreach::Growth.new.week(1).followers
  end

  test "Xtend ticks replies, circle replies, posts, and analytics from data; the rest waits for a tick" do
    ada = Person.create!(x_id: "7", handle: "ada", name: "Ada")
    ada.add_tags!([ "circle" ])
    bob = Person.create!(x_id: "8", handle: "bob", name: "Bob")
    at = Time.zone.local(2026, 11, 10, 9)
    ReplyEvent.create!(person: ada, x_id: "71", target_x_id: "81", direction: "outgoing", source: "x_capture", occurred_at: at, confirmed_at: at)
    ReplyEvent.create!(person: bob, x_id: "72", target_x_id: "82", direction: "outgoing", source: "x_capture", occurred_at: at, confirmed_at: at)
    X::AccountDay.create!(day: Date.new(2026, 11, 9), observed_at: at, counts: { "ProfilePic" => { "false" => 6 } })
    Outreach::GrowthCheck.create!(week: 2, key: "story")

    growth = Outreach::Growth.new(today: Date.new(2026, 11, 14))
    items = growth.checklist(2).to_h { |key, _label, _why, kind, done, detail| [ key, [ kind, done, detail ] ] }
    assert_equal [ :auto, false, "2 of 100" ], items["replies"]
    assert_equal [ :auto, false, "1 of 2 (50%)" ], items["circle"]
    assert_equal [ :auto, true, "Collected this week" ], items["analytics"]
    assert_equal [ :manual, true, nil ], items["story"]
    assert_equal [ :manual, false, nil ], items["build"]
    assert_not items.key?("profile"), "setup items are week 1 only"
    assert growth.checklist(1).any? { _1.first == "profile" }
    assert_equal 6, growth.week(2).visits
    assert_nil growth.week(3).visits
  end

  test "the circle lists people not yet replied to this week first, with a fresh post they haven't had a reply on" do
    run = X::SyncRun.create!(dataset: "posts", owner_x_id: "1", request_key: SecureRandom.uuid, mode: "capture", status: "completed", page_limit: 1, upper_bound: Time.current)
    ada = Person.create!(x_id: "7", handle: "ada", name: "Ada")
    cy = Person.create!(x_id: "9", handle: "cy", name: "Cy")
    [ ada, cy ].each { _1.add_tags!([ "circle" ]) }
    travel_to Time.zone.local(2026, 11, 11, 12) do
      ReplyEvent.create!(person: ada, x_id: "71", target_x_id: "81", direction: "outgoing", source: "x_capture", occurred_at: 1.day.ago, confirmed_at: 1.day.ago)
      X::SourcePost.create!(x_id: "91", author_x_id: "9", body: "Shipping today", published_at: 3.hours.ago, x_sync_run: run)
      X::SourcePost.create!(x_id: "81", author_x_id: "7", body: "Already answered", published_at: 30.hours.ago, x_sync_run: run)
      members = Outreach::Growth.new(today: Date.current).circle_members(2)
      assert_equal %w[cy ada], members.map { _1.person.handle }
      assert_equal "91", members.first.fresh_post.x_id
      assert_nil members.last.fresh_post
      assert members.last.replied_this_week
    end
  end
end
