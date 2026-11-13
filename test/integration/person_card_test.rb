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
end
