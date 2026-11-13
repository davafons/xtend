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
    run = X::SyncRun.create!(dataset: "posts", mode: "capture", owner_x_id: "999", request_key: SecureRandom.uuid, page_limit: 1, upper_bound: Time.current)
    X::SourcePost.create!(x_id: "5001", author_x_id: "7", body: "Ruby 4 is out", language: "en", published_at: 1.hour.ago, x_sync_run: run)
    get search_path(q: "ruby"), headers: { "Sec-Fetch-Mode" => "cors" }
    assert_response :success
    assert_no_match(/<html/, response.body)
    assert_select "[aria-label=People] a[href='#{person_path(person)}']", text: /Ada Ruby/ do
      assert_select "[data-slot=avatar]"
    end
    assert_select "[aria-label=Drafts] a", text: /Ruby tips.*Idea/m
    assert_select "[aria-label=Tags] a[href='#{people_path(tag: "ruby")}']", text: /1 person/ do
      assert_select "[data-slot=avatar]"
    end
    assert_select "[aria-label=Posts] a[href='https://x.com/i/status/5001'][target=_blank]", text: /Ada Ruby.*Ruby 4 is out/m
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
