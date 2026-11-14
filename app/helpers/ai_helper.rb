module AIHelper
  # What to say to a connected assistant to run one of Xtend's tasks (Mcp::Prompts). Works with clients that offer
  # MCP prompts and with those that only call tools, through get_task.
  def ai_task_phrase(task, **arguments)
    detail = arguments.map { |key, value| " for #{key == :handle ? "@#{value}" : value}" }.join
    "Run the Xtend task #{task}#{detail}."
  end

  # A copy button for a task, with the full prompt for assistants without the connector behind a disclosure.
  def ai_task_copy(task, fallback: nil, label: "Copy request for your AI", **arguments)
    phrase = ai_task_phrase(task, **arguments)
    tag.div(class: "flex flex-col gap-related") do
      safe_join([
        tag.div(class: "flex flex-wrap items-center gap-related") do
          safe_join([ lc_copy_button(label, value: phrase, variant: :secondary, size: :sm),
            tag.span("“#{phrase}”", class: "text-caption text-muted-foreground") ])
        end,
        (lc_collapsible(title: "No connector? Copy the full prompt", card: false, indicator: :chevron, button: { variant: :ghost, size: :sm }) do
          tag.div(class: "flex flex-col gap-related") do
            safe_join([ tag.div(lc_copy_button("Copy full prompt", value: fallback, variant: :secondary, size: :sm)),
              tag.p(fallback, class: "whitespace-pre-wrap rounded-2xl bg-tile p-content text-caption") ])
          end
        end if fallback)
      ].compact)
    end
  end

  def ai_change_summary(change)
    payload = change.payload
    case change.kind
    when "tags" then [ payload["tags"].join(", "), payload["reason"] ].compact.join(": ")
    when "note" then payload["text"]
    when "reminder" then "#{payload['reason']} (#{Date.iso8601(payload['due_on']).strftime('%-d %b')})"
    when "recap" then payload["summary"]
    else payload.except("observed_at").map { |key, value| "#{key.humanize}: #{value}" }.join(" · ")
    end
  end
end
