require "test_helper"

class ListsTest < ActionDispatch::IntegrationTest
  setup do
    @ada = Person.create!(x_id: "7", handle: "ada", name: "Ada")
  end

  test "you create a list, add people by handle, move them up the ladder, and see each view" do
    get lists_path
    assert_response :success
    assert_select "a", text: /Inner circle/

    post lists_path, params: { list: { name: "Tokyo devs", cadence_days: "30" } }
    tokyo = List.find_by!(name: "Tokyo devs")
    assert_redirected_to list_path(tokyo)
    assert_equal 30, tokyo.cadence_days

    post list_memberships_path(tokyo), params: { handle: "https://x.com/Ada" }
    post list_memberships_path(tokyo), params: { handle: "@newface" }
    assert_equal %w[ada newface], tokyo.people.order(:handle).pluck(:handle)

    circle = List.tier("circle")
    post list_memberships_path(circle), params: { person_id: @ada.id }
    post list_memberships_path(List.tier("inner")), params: { person_id: @ada.id }
    assert_equal "Inner circle", @ada.reload.tier_list.name

    get list_path(tokyo)
    assert_response :success
    assert_select "[data-slot=badge]", text: "Inner circle"
    get list_path(List.tier("inner"))
    assert_select "[aria-label='Tier for Ada'] button[aria-pressed=true]", text: "Inner circle"
    get people_tend_path
    assert_response :success
    assert_select "h2", text: "Due now"
    get people_board_path
    assert_response :success
    assert_select "h2", text: /Circle/
    get person_path(@ada)
    assert_select "h2", text: /Lists/
    get people_path(list: tokyo.id)
    assert_select "tbody tr", 2
    get network_path(list: tokyo.id)
    assert_response :success

    delete list_membership_path(tokyo, @ada)
    assert_not tokyo.people.include?(@ada)
    delete list_path(circle)
    assert List.exists?(circle.id), "tiers stay"
    delete list_path(tokyo)
    assert_not List.exists?(tokyo.id)
  end
end
