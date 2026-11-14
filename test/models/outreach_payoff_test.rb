require "test_helper"

class OutreachPayoffTest < ActiveSupport::TestCase
  def reply_to(handle, x_id:, followers:, visits:, follows: 0)
    person_x_id = "9#{handle.sum}"
    ingest(x_id: x_id, target_x_id: "8#{x_id}", person_profile: profile(x_id: person_x_id, handle: handle, name: handle))
    Person.find_by!(x_id: person_x_id).tap { |person| person.update!(followers_count: followers) }
    X::PostAnalytic.create!(post_x_id: x_id, observed_at: Time.current, metrics: { "ProfileVisits" => visits, "Follows" => follows })
  end

  test "a size band lifts openings only with enough replies that paid off with more than one person" do
    reply_to("ada", x_id: "1", followers: 500, visits: 6, follows: 1)
    reply_to("ada", x_id: "2", followers: 500, visits: 1)
    reply_to("bob", x_id: "3", followers: 800, visits: 0)
    reply_to("cy", x_id: "4", followers: 3_000, visits: 0)
    reply_to("di", x_id: "5", followers: 3_000, visits: 0)
    reply_to("ed", x_id: "6", followers: 3_000, visits: 1)
    payoff = Outreach::Payoff.new
    small = X::Account.new(followers_count: 900)

    assert_equal 1, payoff.bands.fetch("under 1K").paying_people
    assert_nil payoff.lift(small), "one person's replies don't make a pattern"

    reply_to("flo", x_id: "7", followers: 300, visits: 2)
    payoff = Outreach::Payoff.new
    points, reason = payoff.lift(small)
    assert_operator points, :>, 0
    assert_match(/Accounts with under 1K followers: 9 profile visits, 1 follow from 4 replies/, reason)
    assert_nil payoff.lift(X::Account.new(followers_count: 3_500)), "a band doing worse than usual is never lifted, nor buried"
  end

  test "someone whose replies paid off before is lifted the most, whatever their size" do
    reply_to("ada", x_id: "1", followers: 50_000, visits: 3)
    ada = Person.find_by!(handle: "ada")
    points, reason = Outreach::Payoff.new.lift(ada)
    assert_equal Outreach::Payoff::MAX_POINTS, points
    assert_equal "Your replies to them brought 3 profile visits", reason
  end
end
