require "test_helper"

class PersonCardTest < ActionDispatch::IntegrationTest
  test "hovering a person loads a card with where you stand, your notes, tags and an open reminder" do
    ingest(x_id: "7001", target_x_id: "8001", person_profile: profile(x_id: "7", handle: "ada", name: "Ada"))
    person = Person.find_by!(handle: "ada")
    person.update!(notes: "Met at RubyKaigi", description: "Builds engines")
    person.add_tags!([ "ruby" ])
    person.reminders.create!(reason: "Ask about the talk", due_on: Date.current)

    get people_path
    assert_select "[data-controller=lc-hovercard][data-lc-hovercard-src-value=?] a[href=?]", person_card_path(person), person_path(person)

    get person_card_path(person)
    assert_response :success
    assert_no_match(/<html/, response.body)
    assert_select "a[href=?]", person_path(person), text: "Ada"
    assert_select "p", text: /Builds engines/
    assert_select "p", text: /Your notes: Met at RubyKaigi/
    assert_select "span", text: "#ruby"
    assert_select "p", text: /Ask about the talk/
    assert_match(/1<\/span> from you/, response.body)
  end

  test "a person's posts show the counts X last showed, with when they were seen" do
    ingest(x_id: "7001", target_x_id: "8001", person_profile: profile(x_id: "7", handle: "ada", name: "Ada"))
    person = Person.find_by!(x_id: "7")
    run = X::SyncRun.create!(dataset: "posts", mode: "capture", owner_x_id: "999", request_key: SecureRandom.uuid, page_limit: 1, upper_bound: Time.current)
    X::SourcePost.create!(x_id: "8001", author_x_id: "7", body: "Engines are fun", published_at: 2.days.ago, x_sync_run: run,
      like_count: 1234, reply_count: 5, view_count: 50_000, metrics_observed_at: Time.zone.local(Date.current.year, 1, 3, 9, 30))

    get person_path(person)
    assert_select "[title=?]", "1,234 likes | As seen on X 3 Jan, 09:30"
    assert_select "[title=?]", "50,000 views | As seen on X 3 Jan, 09:30"
  end
end
