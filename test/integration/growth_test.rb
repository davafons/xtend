require "test_helper"

class GrowthTest < ActionDispatch::IntegrationTest
  test "you start a plan from your follower count, tick what Xtend can't see, and see your circle" do
    Current.workspace.update!(owner_followers_count: 170, owner_counts_seen_at: 1.hour.ago)
    get growth_path
    assert_select "h2", text: "Start a growth plan"
    assert_select "p", text: /your 170 followers/

    patch growth_path, params: { growth: { goal: 100 } }
    assert_redirected_to growth_path
    assert_nil Current.workspace.reload.growth_started_on

    patch growth_path, params: { growth: { goal: 1000 } }
    Current.workspace.reload
    assert_equal Date.current, Current.workspace.growth_started_on
    assert_equal 170, Current.workspace.growth_start_followers

    ada = Person.create!(x_id: "7", handle: "ada", name: "Ada")
    ada.add_tags!([ "circle" ])
    get growth_path
    assert_response :success
    assert_select "h2", text: /Week 1 of 16/
    assert_select "[data-slot=stat]", text: /checkpoint\s*180/
    assert_select "#growth-replies", text: /0 of 100/
    assert_select "#growth-story button", text: "Done"
    assert_select "li", text: /Ada.*Never replied/m

    post growth_check_path, params: { week: 1, key: "story" }
    assert_redirected_to growth_path(week: 1)
    follow_redirect!
    assert_select "#growth-story button", text: "Undo"
    delete growth_check_path, params: { week: 1, key: "story" }
    assert_equal 0, Outreach::GrowthCheck.count
    post growth_check_path, params: { week: 1, key: "replies" }
    assert_response :unprocessable_entity
    assert_equal 0, Outreach::GrowthCheck.count

    patch growth_path, params: { growth: { goal: 2000 } }
    assert_equal 2000, Current.workspace.reload.growth_goal
    assert_equal Date.current, Current.workspace.growth_started_on
  end
end
