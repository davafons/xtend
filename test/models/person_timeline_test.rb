require "test_helper"

class PersonTimelineTest < ActiveSupport::TestCase
  test "timeline merges replies, follow changes and decisions newest first" do
    person = ingest(direction: "incoming", occurred_at: 2.years.ago).person
    ingest(x_id: "7002", target_x_id: "8002", occurred_at: 1.day.ago)
    snapshot("following", [person], observed_at: 3.days.ago)
    snapshot("following", [], observed_at: 2.hours.ago)
    person.create_pin!
    Follow::Review.record!(person, "keep")

    entries = person.reload.timeline.entries
    assert_equal entries.map(&:at), entries.map(&:at).sort.reverse
    titles = entries.map(&:title)
    assert_includes titles, "You replied to A Builder"
    assert_includes titles, "A Builder replied to you"
    assert_includes titles, "You were following them at the first complete following check"
    assert_includes titles, "No longer in your following list"
    assert_includes titles, "You chose to keep following"
    assert_includes titles, "You pinned them"
    assert_equal({ "conversation" => 2, "follows" => 2, "decisions" => 4 }, person.timeline.counts)
  end

  test "incomplete following checks do not create follow changes" do
    person = Person.resolve_profile!(profile)
    snapshot("following", [person], observed_at: 2.days.ago)
    snapshot("following", [], complete: false, observed_at: 1.hour.ago)
    assert_equal ["You were following them at the first complete following check"],
      person.timeline.select { |entry| entry.category == "follows" }.map(&:title)
  end

  test "follower baseline is not presented as a known follow date" do
    person = Person.resolve_profile!(profile)
    Follow::FollowerPeriod.observe!(snapshot("followers", [person], observed_at: 1.hour.ago))
    entry = person.timeline.find { |item| item.category == "follows" }
    assert_equal "Already following you at the first complete follower check", entry.title
    assert_match "start date is unknown", entry.detail
  end

  test "profile details from X are sanitized and kept across sparse refreshes" do
    row = X::Payload.profile({ "id" => "101", "username" => "builder", "name" => "A Builder", "location" => "Tokyo",
      "profile_banner_url" => "https://pbs.twimg.com/profile_banners/101/1700000000", "created_at" => "2015-03-01T00:00:00.000Z",
      "public_metrics" => { "followers_count" => 1234, "following_count" => 56, "tweet_count" => 7890 },
      "entities" => { "url" => { "urls" => [ { "expanded_url" => "https://example.com" } ] } } })
    person = Person.resolve_profile!(Person.profile_from_x(row))
    assert_equal [ "Tokyo", 1234, 56, 7890, "https://example.com" ], [ person.location, person.followers_count, person.following_count, person.posts_count, person.website_url ]
    assert_equal "https://pbs.twimg.com/profile_banners/101/1700000000/1500x500", person.banner_image_url
    assert_equal 2015, person.joined_x_at.year
    Person.resolve_profile!(profile)
    assert_equal 1234, person.reload.followers_count
    bad = X::Payload.profile({ "id" => "5", "username" => "x", "name" => "X", "public_metrics" => { "followers_count" => "lots" },
      "entities" => { "url" => { "urls" => [ { "expanded_url" => "javascript:alert(1)" } ] } } })
    assert_nil bad["followers_count"]
    assert_nil bad["website_url"]
  end

  test "profile avatars only accept X image hosts" do
    row = { "id" => "5", "username" => "builder", "name" => "Builder" }
    assert_equal "https://pbs.twimg.com/profile_images/1/a_normal.jpg",
      X::Payload.profile(row.merge("profile_image_url" => "https://pbs.twimg.com/profile_images/1/a_normal.jpg"))["profile_image_url"]
    assert_nil X::Payload.profile(row.merge("profile_image_url" => "https://evil.example/x.jpg"))["profile_image_url"]
    person = Person.resolve_profile!(profile.merge(avatar_url: "https://pbs.twimg.com/profile_images/1/a_normal.jpg"))
    assert_equal "https://pbs.twimg.com/profile_images/1/a_bigger.jpg", person.avatar_image_url
    Person.resolve_profile!(profile)
    assert_equal "https://pbs.twimg.com/profile_images/1/a_normal.jpg", person.reload.avatar_url
  end
end
