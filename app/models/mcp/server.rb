# A minimal MCP server over Streamable HTTP, answering JSON-RPC requests with JSON (no SSE stream).
# Supports initialize, ping, tools/list, tools/call, prompts/list, and prompts/get. Tools live in Mcp::Tools, prompts
# (Xtend's tasks) in Mcp::Prompts.
class Mcp::Server
  PROTOCOL_VERSIONS = %w[2025-06-18 2025-03-26 2024-11-05].freeze
  INSTRUCTIONS = <<~TEXT.squish
    Xtend, the owner's X relationship app, shared with whichever AI assistant he connects. Read tools return collected evidence with coverage
    limits: missing history is not proof that nothing happened, and an unknown follow state is not a non-follow.
    Write tools change only Xtend: tags, recaps, profile facts, notes, reminders, post drafts, and unverified reply targets.
    When the owner lets AI apply changes they apply at once and he can undo each one; otherwise they wait for his review, and
    each result says which. Nothing here posts, replies, follows, unfollows, messages, or marks a reply as sent.
    Start with get_owner_profile for his interests, rules, and tag vocabulary, and call list_ai_changes before writing so
    you don't repeat work. For a whole task, use a prompt or get_task: #{Mcp::Prompts.names.join(', ')}.
    When the owner shares a post idea, save it with save_post_idea, adding variations if he asks. For a recap of his week,
    use get_week_review. Omit facts you did not observe instead of guessing.
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
        capabilities: { tools: { listChanged: false }, prompts: { listChanged: false } },
        serverInfo: { name: "xtend", title: "Xtend", version: "0.1.0" },
        instructions: INSTRUCTIONS }
    when "ping" then {}
    when "tools/list" then { tools: Mcp::Tools.definitions }
    when "tools/call" then call_tool(params)
    when "prompts/list" then { prompts: Mcp::Prompts.definitions }
    when "prompts/get" then get_prompt(params)
    else raise Error.new(-32601, "Unknown method: #{method.to_s.first(80)}")
    end
  end

  def get_prompt(params)
    arguments = params["arguments"] || {}
    raise Error.new(-32602, "arguments must be an object.") unless arguments.is_a?(Hash)
    Mcp::Prompts.get(params["name"].to_s, arguments)
  rescue ArgumentError => error
    raise Error.new(-32602, error.message)
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
