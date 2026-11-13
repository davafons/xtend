# The OAuth 2.1 authorization server that links AI clients (over MCP) and the browser extension to a workspace,
# in place of pasted tokens. Its records authenticate requests before any workspace is known, so they are auth
# records like sessions, not WorkspaceScoped owner data.
module Oauth
  def self.table_name_prefix = "oauth_"
end
