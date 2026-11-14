require "test_helper"

class WeekTest < ActionDispatch::IntegrationTest
  test "the week in review shows what you did, what it brought with honest coverage, the best reply, and what's next" do
    ingest(x_id: "7001", target_x_id: "8001", occurred_at: 2.days.ago, person_profile: profile(x_id: "7", handle: "ada", name: "Ada"))
    ingest(x_id: "9001", target_x_id: "7001", direction: "incoming", classification: "continuation", occurred_at: 1.day.ago,
      person_profile: profile(x_id: "7", handle: "ada", name: "Ada"))
    X::PostAnalytic.create!(post_x_id: "7001", body: "@ada Great point", observed_at: 1.hour.ago, metrics: { "Impressions" => 300, "ProfileVisits" => 4, "Follows" => 1 })
    X::AccountDay.create!(day: 3.days.ago.to_date, observed_at: 1.hour.ago, counts: { "Displayed" => { "false" => 900 }, "Follow" => { "false" => 2 } })
    Person.find_by!(x_id: "7").reminders.create!(reason: "Ask about the talk", due_on: Date.current)

    get week_path
    assert_response :success
    assert_select "[data-slot=stat]", text: /replies\s*1/
    assert_select "[data-slot=stat]", text: /of 1 answered\s*1/
    assert_select "p", text: /Answers can still be missing/
    assert_select "[data-slot=stat]", text: /impressions\s*900/
    assert_select "a[href=?]", "https://x.com/i/status/7001", text: "Great point"
    assert_select "li", text: /Ask about the talk/

    get week_path(weeks_ago: 3)
    assert_select "p", text: /No X analytics for this week/
    assert_select "p", text: /None of this week's replies have X analytics yet/
  end
end
