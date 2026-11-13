module DraftsHelper
  # One row of tabs for every compose view, underlined like X's timeline tabs.
  def compose_tabs(counts:, status: nil, inspiration: false)
    items = [ [ "Open", drafts_path, !inspiration && status.nil?, counts.except("posted").values.sum ] ]
    items += Draft::STATUSES.map { |key, label| [ label, drafts_path(status: key), !inspiration && status == key, counts.fetch(key, 0) ] }
    items << [ "Inspiration", ideas_drafts_path, inspiration, nil ]
    tag.nav(aria: { label: "Compose" }, class: "flex border-b border-border") do
      safe_join(items.map do |label, path, current, count|
        link_to path, aria: { current: ("page" if current) },
          class: "group flex flex-1 justify-center px-related text-small text-muted-foreground transition-colors hover:bg-accent/40 hover:text-foreground aria-[current=page]:font-semibold aria-[current=page]:text-foreground" do
          tag.span(class: "relative flex items-center gap-tight py-content") do
            safe_join([
              label,
              (tag.span(count, class: "tabular-nums font-normal text-muted-foreground") if count&.positive?),
              tag.span(class: "absolute inset-x-0 bottom-0 hidden h-1 rounded-full bg-you group-aria-[current=page]:block", aria: { hidden: true })
            ].compact)
          end
        end
      end)
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
