require "test_helper"

class AppearanceTest < ActionDispatch::IntegrationTest
  test "the theme defaults to dim and rejects unknown themes" do
    get people_path
    assert_select "html[data-palette=dim]"

    patch appearance_path(theme: "aurora"), headers: { "HTTP_REFERER" => people_url }
    assert_redirected_to people_url
    assert_equal "dim", User.sole.theme
  end
end
