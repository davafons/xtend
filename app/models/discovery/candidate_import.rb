class Discovery::CandidateImport
  class Invalid < StandardError; end
  MAX_BYTES = 1.megabyte
  MAX_POSTS = 200

  def self.call(text)
    raise Invalid, "Choose a JSON file smaller than 1 MB." if text.bytesize > MAX_BYTES
    document = JSON.parse(text)
    raise Invalid, "Use a discovery-v1 document with a posts array." unless document.is_a?(Hash) && document["format"] == "twitter-crm-discovery-v1" && document["posts"].is_a?(Array)
    raise Invalid, "Import up to 200 posts at a time." if document["posts"].size > MAX_POSTS

    Post.transaction do
      document["posts"].each do |row|
        profile = row.fetch("person")
        person = Person.find_or_initialize_by(x_id: profile.fetch("x_id").to_s)
        person.assign_attributes(profile.slice("handle", "name", "description"))
        person.save!
        post = Post.find_or_initialize_by(x_id: row.fetch("x_id").to_s)
        post.assign_attributes(person: person, body: row.fetch("body"),
          language: row.fetch("language", "en"), topic: row["topic"],
          match_reason: row["match_reason"], source: "import", published_at: Time.iso8601(row.fetch("published_at")))
        assessment = Discovery::Assessment.call(body: post.body, description: person.description,
          interests: Current.workspace.interests, handle: person.handle, selected: true)
        post.rank = assessment[:rank]
        post.save!
      end
    end
    document["posts"].size
  rescue JSON::ParserError, KeyError, ArgumentError, TypeError, NoMethodError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    raise Invalid, "The import could not be read. Check person IDs, handles, tweet IDs, text, and ISO-8601 dates."
  end
end
