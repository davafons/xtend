require "test_helper"
require_relative "../test_helpers/web_capture_helper"

class XCaptureFollowListsTest < ActiveSupport::TestCase
  include WebCaptureHelper

  setup do
    @owner = Current.workspace.owner_x_id
  end

  def following(id, handle)
    web_user(id, handle).merge("relationship_perspectives" => { "following" => true })
  end

  def follower(id, handle)
    web_user(id, handle).merge("relationship_perspectives" => { "followed_by" => true })
  end

  def owner_profile(followers:, following:)
    user = owner_user
    user["relationship_counts"] = { "followers" => followers, "following" => following }
    web_response("UserByScreenName", { "data" => { "user" => { "result" => user } } })
  end

  test "scrolling your whole following list across batches builds a complete list that replaces the older one" do
    gone = Person.resolve_profile!(profile(x_id: "201", handle: "gone"))
    snapshot("following", [ gone ], observed_at: 3.days.ago)

    first = capture!(owner_profile(followers: 1, following: 3), own_list_page("Following", [ following("211", "one"), following("212", "two") ], bottom: "100|a"))
    assert_equal 1, first[:list_pages]
    assert_nil Follow::Snapshot.latest_complete("following").next_cursor, "the old API list still counts while scrolling"
    assert Follow::Graph.latest.following?(gone)

    result = capture!(own_list_page("Following", [ following("213", "three") ], cursor: "100|a", bottom: "50|b"),
      own_list_page("Following", [], cursor: "50|b", bottom: "0|c"))

    list = Follow::Snapshot.latest_complete("following")
    assert_equal 1, result[:lists_completed]
    assert_equal "x_capture", list.source
    assert_equal %w[211 212 213], list.people.order(:x_id).pluck(:x_id)
    assert_equal 3, list.expected_count
    assert_not Follow::Graph.latest.following?(gone), "someone missing from a complete list isn't followed anymore"
    assert_equal 0, X::Read.count
  end

  test "a missed page or a list well short of your profile's count never completes" do
    capture!(owner_profile(followers: 0, following: 40))
    capture!(own_list_page("Following", [ following("221", "one") ], bottom: "100|a"))
    skipped = capture!(own_list_page("Following", [ following("223", "three") ], cursor: "90|z", bottom: "0|end"))
    assert_equal 0, skipped[:list_pages], "a page that doesn't continue the list is ignored"
    assert_nil Follow::Snapshot.latest_complete("following")

    capture!(own_list_page("Following", [ following("222", "two") ], cursor: "100|a", bottom: "0|end"))
    assert_nil Follow::Snapshot.latest_complete("following"), "2 of 40 accounts is not a complete list"

    capture!(owner_profile(followers: 0, following: 2))
    capture!(own_list_page("Following", [ following("221", "one") ], bottom: "100|a"),
      own_list_page("Following", [ following("222", "two") ], cursor: "100|a", bottom: "0|end"))
    assert_equal 2, Follow::Snapshot.latest_complete("following").people.count
    assert_equal 1, Follow::Snapshot.where(source: "x_capture").count, "a new first page replaces an unfinished list"
  end

  test "a complete follower list from the capture dates new and lost followers" do
    stays = Person.resolve_profile!(profile(x_id: "231", handle: "stays"))
    leaves = Person.resolve_profile!(profile(x_id: "232", handle: "leaves"))
    Follow::FollowerPeriod.observe!(snapshot("followers", [ stays, leaves ], observed_at: 2.days.ago))

    capture!(owner_profile(followers: 2, following: 0),
      own_list_page("Followers", [ follower("231", "stays"), follower("233", "arrives") ], bottom: "0|end"))

    assert Follow::Snapshot.latest_complete("followers").fresh?
    assert_equal [ "arrives" ], Follow::FollowerPeriod.known_starts.ongoing.map { |period| period.person.handle }
    assert_equal [ "leaves" ], Follow::FollowerPeriod.ended.map { |period| period.person.handle }
  end

  test "someone else's follower list is only graph context" do
    capture!(web_response("Followers", web_user_list([ web_user("241", "fan") ], bottom: "0|end"), variables: { "userId" => "555" }))

    assert_equal 0, Follow::Snapshot.count
    assert X::FollowEdge.exists?(follower_x_id: "241", followed_x_id: "555")
  end

  test "a complete following list confirms the unfollows you reported" do
    gone, stayed = %w[251 252].map { |id| Person.resolve_profile!(profile(x_id: id, handle: "p#{id}")) }
    snapshot("following", [ gone, stayed ], observed_at: 3.days.ago)
    travel_to(2.days.ago) { [ gone, stayed ].each { |person| Follow::Review.record!(person, "reported_unfollow") } }

    capture!(own_list_page("Following", [ following("252", "p252") ], bottom: "0|end"))

    assert_equal "unfollowed", Follow::Review.find_by!(person: gone).decision
    assert_not Follow::Review.exists?(person: stayed), "still on a newer list: the report was wrong, so they return to review"

    travel 1.hour do
      late = Person.resolve_profile!(profile(x_id: "253", handle: "p253"))
      snapshot("following", [ late ], observed_at: 1.minute.ago)
      Follow::Review.record!(late, "reported_unfollow")
      Follow::Review.settle_reported!
      assert_equal "reported_unfollow", Follow::Review.find_by!(person: late).decision, "newer than every list and sighting: waits"
      travel 1.minute
      capture!(web_response("UserByScreenName", { "data" => { "user" => { "result" => web_user("253", "p253").merge("relationship_perspectives" => { "following" => false }) } } }))
      assert_equal "unfollowed", Follow::Review.find_by!(person: late).decision, "x.com showing you don't follow them settles it"
    end
  end
end
