# bin/rails rails_schema:generate writes tmp/schema.html: the models grouped by domain namespace, as AGENTS.md lays
# them out, with top-level models under Core. Development only, and outside public/ so the app never serves it.
if Rails.env.development?
  require "rails/schema"

  Rails::Schema.configure do |config|
    config.output_path = Rails.root.join("tmp/schema.html").to_s
    config.title = "Xtend data model"
    config.theme = :dark
    config.expand_columns = false
    config.collapse_groups = false
    config.exclude_models = [ "ActiveStorage::*", "ActionText::*", "ActionMailbox::*", "SolidQueue::*", "SolidCache::*", "SolidCable::*" ]
    config.model_schema_group = ->(model) { [ model.name.include?("::") ? model.name.split("::").first : "Core" ] }
  end
end
