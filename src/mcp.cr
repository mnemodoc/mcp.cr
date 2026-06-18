require "json"
require "log"

require "./mcp/errors"
require "./mcp/tool"
require "./mcp/content"
require "./mcp/tool_result"
require "./mcp/tool_annotations"
require "./mcp/arguments"
require "./mcp/progress"
require "./mcp/session"
require "./mcp/server"
require "./mcp/handler"
require "./mcp/transport/stdio"
require "./mcp/transport/http"

# Self-contained MCP (Model Context Protocol) server toolkit: protocol handling,
# tool registry, and stdio / Streamable-HTTP transports. Zero runtime
# dependencies beyond the Crystal standard library.
module MCP
  VERSION          = "1.0.0"
  PROTOCOL_VERSION = "2025-06-18"
  Log              = ::Log.for("mcp")
end
