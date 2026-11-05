require "test_helper"
require "tmpdir"

class ArchiveImportFlowTest < ActionDispatch::IntegrationTest
  test "uploading a non-zip shows an error and the follow review shows quiet reasons" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "notes.zip")
      File.write(path, "plain text")
      post x_archive_imports_path, params: { file: Rack::Test::UploadedFile.new(path, "application/zip") }
      assert_redirected_to settings_path(anchor: "archive")
      follow_redirect!
      assert_includes response.body, "Choose the .zip file X sent you."
    end

    old = ingest(occurred_at: 100.days.ago).person
    snapshot("following", [old])
    snapshot("followers", [])
    get follow_reviews_path
    assert_includes response.body, "Quiet for 100 days"
    assert_includes response.body, "You replied ·"
    get follow_reviews_path(quiet: 180)
    assert_includes response.body, "done for now"
  end
end
