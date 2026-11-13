module DraftsHelper
  # One row of tabs for every compose view, underlined like X's timeline tabs.
  def compose_tabs(counts:, status: nil, inspiration: false)
    lc_tab_bar label: "Compose", fill: true do |bar|
      safe_join([
        bar.link("Open", drafts_path, current: !inspiration && status.nil?, count: counts.except("posted").values.sum.nonzero?),
        *Draft::STATUSES.map { |key, label| bar.link(label, drafts_path(status: key), current: !inspiration && status == key, count: counts.fetch(key, 0).nonzero?) },
        bar.link("Inspiration", ideas_drafts_path, current: inspiration)
      ])
    end
  end

  # The owner's display name and handle for X-style post headers.
  def owner_identity
    @owner_identity ||= begin
      handle = X::Connection.current&.username
      person = Person.find_by(x_id: Current.workspace.owner_x_id) if Current.workspace.owner_x_id.present?
      [ person&.name.presence || handle || "You", handle ]
    end
  end
end
