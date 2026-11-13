require "test_helper"

class AppearanceTest < ActionDispatch::IntegrationTest
  test "the theme defaults to aurora and switches to dim for the signed-in user" do
    get people_path
    assert_select "html[data-palette=aurora]"
    assert_select "form[action='#{appearance_path(theme: "dim")}'] button", text: /Dim theme/

    patch appearance_path(theme: "dim"), headers: { "HTTP_REFERER" => people_url }
    assert_redirected_to people_url
    follow_redirect!
    assert_select "html[data-palette=dim]"

    patch appearance_path(theme: "sepia")
    assert_equal "dim", User.sole.theme
  end
end
