require "test_helper"

class TagTest < ActiveSupport::TestCase
  test "tags are normalized, added once, and survive profile sync" do
    person = Person.resolve_profile!(profile)
    assert_equal %w[tokyo ios\ dev], person.add_tags!("#Tokyo, iOS  Dev, tokyo").map(&:name)
    assert_empty person.add_tags!("TOKYO")
    Person.resolve_profile!(profile(name: "Renamed Builder"))
    assert_equal ["ios dev", "tokyo"], person.reload.tags.map(&:name)
    assert_equal ["owner"], person.person_tags.map(&:source).uniq
  end

  test "removing the last use of a tag removes the tag, and tags stay per workspace" do
    person = Person.resolve_profile!(profile)
    person.add_tags!("tokyo")
    other = Workspace.create!(name: "Other", owner_x_id: "888")
    Current.set(workspace: other) { Person.resolve_profile!(profile(x_id: "202", handle: "theirs")).add_tags!("tokyo") }
    person.person_tags.first.destroy!
    assert_equal 0, Tag.count
    assert_equal 1, Current.set(workspace: other) { Tag.count }
  end

  test "people can be filtered by tag or by having none" do
    tagged = Person.resolve_profile!(profile)
    untagged = Person.resolve_profile!(profile(x_id: "102", handle: "plain"))
    tagged.add_tags!("tokyo")
    assert_equal [tagged], Person.tagged("Tokyo").to_a
    assert_equal [untagged], Person.untagged.to_a
  end

  test "AI tag proposals stage only new tags and apply when accepted" do
    person = Person.resolve_profile!(profile)
    person.add_tags!("tokyo")
    result = AI::Intake.new(via: "paste").call("tags" => [
      { "handle" => "builder", "tags" => ["Tokyo", "indie hacker"], "reason" => "Bio says Tokyo indie hacker" },
      { "handle" => "nobody", "tags" => ["x"] }
    ])
    assert_equal %w[staged rejected], result[:tags].map { |item| item[:status] }
    proposal = AI::Proposal.pending.sole
    assert_equal ["indie hacker"], proposal.payload["tags"]
    assert_equal ["tokyo"], person.reload.tags.map(&:name), "nothing applies before review"
    proposal.accept!
    assert_equal ["indie hacker", "tokyo"], person.reload.tags.map(&:name)
    assert_equal "ai", person.person_tags.joins(:tag).find_by(tags: { name: "indie hacker" }).source
    assert_equal "unchanged", AI::Intake.new(via: "paste").call("tags" => [{ "handle" => "builder", "tags" => ["tokyo"] }])[:tags].first[:status]
  end

  test "the tagging prompt lists untagged people with an X account" do
    Person.resolve_profile!(profile).add_tags!("tokyo")
    Person.resolve_profile!(profile(x_id: "102", handle: "plain", name: "Plain"))
    Person.create!(handle: "grokonly", name: "Grok only")
    assert_equal ["plain"], AI::Classification.batch.map(&:handle)
    prompt = AI::Classification.prompt
    assert_includes prompt, '"handle":"plain"'
    assert_includes prompt, "Reuse these existing tags where they fit: tokyo."
  end
end
