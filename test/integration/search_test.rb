require "test_helper"

class SearchTest < ActionDispatch::IntegrationTest
  test "every page has the search trigger and its commands" do
    get people_path
    assert_select "button[data-slot=search-trigger][aria-controls=lc-search]"
    assert_select "dialog.lc-search [data-slot=search-group][aria-label='Go to'] a[href='#{network_path}']"
    assert_select "dialog.lc-search [data-slot=search-group][aria-label=Actions] a[href='#{new_person_path}']"
  end

  test "the palette's fetch gets matching people, tags, drafts, and commands without the layout" do
    person = Person.resolve_profile!(profile(x_id: "7", handle: "rubyist", name: "Ada Ruby"))
    person.add_tags!([ "ruby" ])
    Draft.create!(body: "Ruby tips for beginners")
    get search_path(q: "ruby"), headers: { "Sec-Fetch-Mode" => "cors" }
    assert_response :success
    assert_no_match(/<html/, response.body)
    assert_select "[aria-label=People] a[href='#{person_path(person)}']", text: /Ada Ruby/
    assert_select "[aria-label=Drafts] a", text: /Ruby tips/
    assert_select "[aria-label=Tags] a[href='#{people_path(tag: "ruby")}']"
    assert_select "a[href='#{people_path(q: "ruby")}']"
    get search_path(q: "netw"), headers: { "Sec-Fetch-Mode" => "cors" }
    assert_select "[aria-label='Go to'] a[href='#{network_path}']"
    assert_select "[aria-label=People]", count: 0
  end

  test "a plain form submit gets a full page" do
    get search_path(q: "x"), headers: { "Sec-Fetch-Mode" => "navigate" }
    assert_select "html main h1", text: "Search"
  end
end
