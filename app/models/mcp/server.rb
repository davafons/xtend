# A minimal MCP server over Streamable HTTP, answering JSON-RPC requests with JSON (no SSE stream).
# Supports initialize, ping, tools/list, and tools/call. Tools live in Mcp::Tools.
class Mcp::Server
  PROTOCOL_VERSIONS = %w[2025-06-18 2025-03-26 2024-11-05].freeze
  INSTRUCTIONS = <<~TEXT.squish
    Xtend, the owner's X relationship app, shared with whichever AI assistant he connects. Read tools return collected evidence with coverage
    limits: missing history is not proof that nothing happened, and an unknown follow state is not a non-follow.
    Write tools only stage proposals for the owner to review or save drafts of his own posts in Compose. They never post,
    reply, follow, unfollow, or message anyone, never apply tags or profile changes, and cannot mark replies as sent.
    Start with get_owner_profile for his interests, rules, and tag vocabulary, and call list_pending_proposals before
    proposing so you add to his review queue instead of repeating it.
    Useful work: (1) Tag people: list_people with filter "untagged", then propose_tags with short public evidence,
    reusing existing tags. (2) Find reply targets: get_session_state and list_known_posts to skip duplicates, public
    X search, then propose_candidate_posts with real source URLs and observed facts. (3) Research someone:
    get_person_context and get_interaction_history, then propose_recap with evidence URLs or propose_person_facts.
    (4) Draft posts: list_network_posts for topics and style that work in his network, list_post_drafts for open
    ideas, then save_post_idea or add_post_variations; for a recap of his week, use his own posts there (author "david", period "7d").
    When the owner shares a post idea, save it with save_post_idea, adding variations if he asks.
    Omit facts you did not observe instead of guessing.
  TEXT

  Error = Class.new(StandardError) do
    attr_reader :code
    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  # Returns the JSON-RPC response hash, or nil for notifications and responses (HTTP 202, no body).
  def handle(message)
    raise Error.new(-32600, "Send one JSON-RPC 2.0 request object.") unless message.is_a?(Hash) && message["jsonrpc"] == "2.0"
    return nil unless message.key?("id") && message.key?("method")
    { jsonrpc: "2.0", id: message["id"], result: dispatch(message["method"], message["params"] || {}) }
  rescue Error => error
    { jsonrpc: "2.0", id: message.is_a?(Hash) ? message["id"] : nil, error: { code: error.code, message: error.message } }
  end

  private

  def dispatch(method, params)
    raise Error.new(-32602, "params must be an object.") unless params.is_a?(Hash)
    case method
    when "initialize"
      requested = params["protocolVersion"]
      { protocolVersion: PROTOCOL_VERSIONS.include?(requested) ? requested : PROTOCOL_VERSIONS.first,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "xtend", title: "Xtend", version: "0.1.0" },
        instructions: INSTRUCTIONS }
    when "ping" then {}
    when "tools/list" then { tools: Mcp::Tools.definitions }
    when "tools/call" then call_tool(params)
    else raise Error.new(-32601, "Unknown method: #{method.to_s.first(80)}")
    end
  end

  def call_tool(params)
    name = params["name"]
    raise Error.new(-32602, "Unknown tool: #{name.to_s.first(80)}") unless Mcp::Tools.names.include?(name)
    arguments = params["arguments"] || {}
    raise Error.new(-32602, "arguments must be an object.") unless arguments.is_a?(Hash)
    result = Mcp::Tools.new.public_send(name, arguments)
    { content: [{ type: "text", text: JSON.generate(result) }], structuredContent: result, isError: false }
  rescue Mcp::Tools::Invalid, AI::Intake::Invalid => error
    { content: [{ type: "text", text: error.message }], isError: true }
  end
end
