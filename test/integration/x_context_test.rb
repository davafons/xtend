require "test_helper"

class XContextTest < ActionDispatch::IntegrationTest
  setup { @token = paste_token("capture") }

  def read_context(handles, token: @token, origin: "chrome-extension://abcdefghijklmnop")
    get x_capture_context_path(handles: handles), headers: { "Origin" => origin, "Authorization" => ("Bearer #{token}" if token) }.compact
  end

  test "the extension reads where you stand with the people x.com shows, with your notes, tags and reminder" do
    ingest(x_id: "7001", target_x_id: "8001", person_profile: profile(x_id: "7", handle: "Ada", name: "Ada"))
    ingest(x_id: "7002", target_x_id: "7001", direction: "incoming", classification: "continuation", person_profile: profile(x_id: "7", handle: "Ada", name: "Ada"))
    ada = Person.find_by!(x_id: "7")
    ada.update!(notes: "Met at RubyKaigi", you_follow: true, you_follow_seen_at: Time.current, follows_you: true, follows_you_seen_at: Time.current)
    ada.add_tags!([ "ruby" ])
    ada.reminders.create!(reason: "Ask about the talk", due_on: Date.current)
    sign_out

    read_context("@ada,stranger,not a handle!")
    assert_response :success
    people = response.parsed_body["people"]
    assert_equal %w[ada stranger], people.keys
    assert_equal({ "known" => false }, people["stranger"], "partial follow lists can't say a stranger follows neither way")
    context = people["ada"]
    assert_equal [ "Mutual", "both" ], context.values_at("follow", "meaning")
    assert_equal({ "from_you" => 1, "from_them" => 1 }, context["replies"])
    assert_match(/They replied to you/, context.dig("latest", "label"))
    assert_equal person_url(ada, show: "conversation"), context.dig("latest", "url")
    assert_equal "Met at RubyKaigi", context["notes"]
    assert_equal "ruby", context.dig("tags", 0, "name")
    assert_equal people_url(tag: "ruby"), context.dig("tags", 0, "url")
    assert_equal [ "Ask about the talk", true ], context["reminder"].values_at("reason", "due")
    assert_equal person_url(ada), context["url"]
  end

  test "with complete follow lists, someone Xtend has no person for follows neither way as of the older check" do
    snapshot("following", [], observed_at: 3.days.ago)
    snapshot("followers", [], observed_at: 1.day.ago)
    read_context("stranger")
    assert_equal({ "known" => false, "follow" => "Neither", "meaning" => "neutral" }, response.parsed_body.dig("people", "stranger"))
    assert_in_delta 3.days.ago, Time.zone.parse(response.parsed_body["follow_checked_at"]), 1.minute
  end

  test "only the extension's capture link from an extension origin can read it" do
    read_context("ada", token: nil)
    assert_response :unauthorized
    read_context("ada", token: paste_token("mcp"))
    assert_response :unauthorized
    read_context("ada", origin: "https://evil.example")
    assert_response :forbidden
  end
end
