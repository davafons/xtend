require "test_helper"

class PeopleAndReviewTest < ActionDispatch::IntegrationTest
  test "people table sorts by most recent reply and filters combine" do
    quiet = Person.resolve_profile!(profile(x_id: "1", handle: "aaquiet", name: "Aa Quiet"))
    recent = ingest(person_profile: profile(x_id: "2", handle: "recent", name: "Zz Recent")).person
    get people_path
    assert_response :success
    assert_select "#recent-people a", text: /Zz Recent/
    assert_select "#recent-people a", text: /Aa Quiet/, count: 0
    table = response.body[response.body.index("<table")..]
    assert_operator table.index("Zz Recent"), :<, table.index("Aa Quiet")
    get people_path(sort: "name")
    table = response.body[response.body.index("<table")..]
    assert_operator table.index("Aa Quiet"), :<, table.index("Zz Recent")
    get people_path(state: "You replied only", q: "recent")
    assert_select "tbody tr", 1
    assert_includes response.body, recent.name
    quiet.update!(notes: "Met at RubyKaigi")
    get people_path(filter: "notes")
    assert_select "tbody tr", 1
    assert_includes response.body, "Met at RubyKaigi"
  end

  test "person page shows a filtered timeline" do
    person = ingest.person
    get person_path(person)
    assert_response :success
    assert_includes response.body, "You replied to A Builder"
    get person_path(person, show: "follows")
    assert_not_includes response.body, "You replied to A Builder"
  end

  test "follow review batch size and decisions keep the chosen batch" do
    people = 7.times.map { |index| Person.resolve_profile!(profile(x_id: (100 + index).to_s, handle: "candidate#{index}", name: "Candidate #{index}")) }
    snapshot("following", people)
    snapshot("followers", [])
    get follow_reviews_path(reason: "quiet", mutuals: "0")
    assert_select "tbody tr", 5
    get follow_reviews_path(reason: "quiet", mutuals: "0", batch: 10)
    assert_select "tbody tr", 7
    post follow_reviews_path(person_id: people.first.id, decision: "defer", reason: "quiet", mutuals: "0", batch: 10)
    assert_redirected_to follow_reviews_path(reason: "quiet", mutuals: "0", batch: 10)
    follow_redirect!
    assert_select "tr[id^=review_person]", 6
    assert_includes response.body, "Deferred"
    assert_equal 6, Person.cleanup_candidates.count
    people.last.update!(followers_count: 50_000)
    get follow_reviews_path(reason: "quiet", sort: "largest")
    assert_select "tr[id^=review_person]:first-child", text: /Candidate 6/
    get follow_reviews_path(reason: "quiet", sort: "name")
    assert_select "tr[id^=review_person]:first-child", text: /Candidate 1/
  end

  test "follow review starts with inactive accounts, mutuals marked, and asks for activity it doesn't have" do
    gone = Person.resolve_profile!(profile(x_id: "401", handle: "gone", name: "Gone Quiet"))
    gone.update!(last_posted_at: 300.days.ago)
    unknown = Person.resolve_profile!(profile(x_id: "402", handle: "unknown", name: "Not Read"))
    snapshot("following", [ gone, unknown ])
    snapshot("followers", [ gone ], observed_at: 3.days.ago)
    get follow_reviews_path
    assert_select "tr[id^=review_person]", 1
    assert_select "tr[id^=review_person]", text: /Gone Quiet.*Mutual/m
    assert_includes response.body, "1 account you follow last posted"
    assert_select "form[action='#{x_sync_runs_path}'] input[name=return_to][value=follow_reviews]"
    get follow_reviews_path(reason: "strangers")
    assert_select "tr[id^=review_person]", 2
    get follow_reviews_path(mutuals: "0")
    assert_includes response.body, "Leaving mutuals out needs a fresh follower list"
  end
end
