require "test_helper"
require "tmpdir"

class ArchivePostsImportFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "an uploaded archive imports in the background and the X data page shows what was added" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "archive.zip")
      generated = 1.day.ago
      tweet = { "id_str" => "9002", "full_text" => "@ada hello", "created_at" => 3.days.ago.utc.strftime("%a %b %d %H:%M:%S +0000 %Y"),
        "in_reply_to_status_id_str" => "5001", "in_reply_to_user_id_str" => "201", "in_reply_to_screen_name" => "ada",
        "entities" => { "user_mentions" => [ { "id_str" => "201", "screen_name" => "ada", "name" => "Ada L" } ] } }
      contents = {
        "data/manifest.js" => { "archiveInfo" => { "generationDate" => generated.iso8601, "isPartialArchive" => false },
          "dataTypes" => { "account" => { "files" => [ { "fileName" => "data/account.js" } ] }, "tweets" => { "files" => [ { "fileName" => "data/tweets.js" } ] } } },
        "data/account.js" => [ { "account" => { "accountId" => "999", "createdAt" => 400.days.ago.iso8601 } } ],
        "data/tweets.js" => [ { "tweet" => tweet } ]
      }
      Zip::OutputStream.open(path) { |zip| contents.each { |name, value| zip.put_next_entry(name); zip.write("window.YTD.x.part0 = #{JSON.generate(value)}") } }

      date = generated.to_date.to_fs(:long)
      assert_enqueued_jobs 1, only: X::ArchiveImportJob do
        post x_archive_imports_path, params: { file: Rack::Test::UploadedFile.new(path, "application/zip") }
      end
      assert_redirected_to x_sources_path(anchor: "archive")
      follow_redirect!
      assert_includes response.body, "Importing your archive of #{date}."
      assert_includes response.body, "Reload to see what was added."
      import = X::ArchiveImport.sole
      assert_equal [ "queued", true ], [ import.status, import.partial ], "an unfinished import never claims coverage"
      assert File.exist?(import.upload_path)

      post x_archive_imports_path, params: { file: Rack::Test::UploadedFile.new(path, "application/zip") }
      follow_redirect!
      assert_includes response.body, "An archive import is already running."

      perform_enqueued_jobs
      assert_equal [ "completed", false ], [ import.reload.status, import.partial ]
      assert_not File.exist?(import.upload_path)
      get x_sources_path
      assert_includes response.body, "1 new post, 1 new reply, 1 person added, and 0 new DMs from your archive of #{date}"
      assert_not_includes response.body, "Reload to see what was added."
      assert_equal "Ada L", Person.find_by!(x_id: "201").name
    end
  end
end
