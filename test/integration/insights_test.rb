require "test_helper"

class InsightsPageTest < ActionDispatch::IntegrationTest
  test "insights shows setup notes without data, then charts with their data table" do
    get insights_path
    assert_response :success
    assert_includes response.body, "No replies or DMs saved for this period."
    assert_includes response.body, "No complete follower check in this period."
    assert_select "[data-controller=chart]", 0

    ingest(occurred_at: 2.days.ago)
    snapshot("followers", [ Person.first ], observed_at: 1.day.ago)

    get insights_path(period: "30d")
    assert_response :success
    assert_select "[data-controller=chart]", 2
    assert_select "button[aria-pressed=true]", text: /Your replies/
    config = JSON.parse(css_select("[data-controller=chart]").first["data-chart-config-value"])
    assert_equal %w[--xtend-you --warning --xtend-message], config["series"].map { |series| series["color"] }
    assert_equal 1, config["series"].first["values"].sum
    assert_select "table.sr-only th", text: "Followers"
    assert_not_includes response.body, "Gained and lost", "a single check is only a baseline"
    assert_equal "/insights", config["zoom"]
    assert_equal config["labels"].size, config["links"].size
    assert_equal [ Date.current.iso8601 ] * 2, config["dates"].last
    assert_select "table.sr-only th[scope=row] a[href=?]", people_path(from: Date.current, to: Date.current)
  end

  test "a dragged range narrows the page and the people list it links to" do
    ingest(x_id: "1", occurred_at: 3.days.ago, person_profile: profile(x_id: "201", handle: "alice"))
    ingest(x_id: "2", occurred_at: 20.days.ago, person_profile: profile(x_id: "202", handle: "bob"))
    from, to = 5.days.ago.to_date, Date.current

    get insights_path(from: from, to: to)
    assert_response :success
    assert_select "a[aria-label^='Remove the date range']"
    assert_select "dd a[href=?]", people_path(from: from, to: to), text: "1"

    get people_path(from: from, to: to)
    assert_response :success
    assert_select "a[aria-label^='Remove the date filter']"
    assert_select "main tbody th", text: /@alice/
    assert_select "main tbody th", text: /@bob/, count: 0

    get insights_path(from: "nonsense", to: to)
    assert_select "a[aria-label^='Remove the date range']", 0
  end

  test "follower changes chart only when a later check gained or lost someone" do
    alice, bob = %w[301 302].map { |id| Person.resolve_profile!(profile(x_id: id, handle: "p#{id}")) }
    Follow::FollowerPeriod.observe!(snapshot("followers", [ alice ], observed_at: 2.days.ago))
    Follow::FollowerPeriod.observe!(snapshot("followers", [ alice ], observed_at: 1.day.ago))

    get insights_path(period: "30d")
    assert_includes response.body, "No followers gained or lost across 1 later check"

    Follow::FollowerPeriod.observe!(snapshot("followers", [ bob ], observed_at: 1.hour.ago))
    get insights_path(period: "30d")
    assert_select "h3", text: "Gained and lost at each check"
    config = JSON.parse(css_select("[data-controller=chart]").last["data-chart-config-value"])
    assert_equal [ [ nil, 0, 1 ], [ nil, 0, -1 ] ], config["series"].map { |series| series["values"] }
  end
end
