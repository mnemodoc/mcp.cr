# A Streamable HTTP server with a progress-reporting tool.
#
#   crystal run examples/streaming_http.cr
#
# Liveness:
#   curl http://127.0.0.1:8765/health
#
# Synchronous call (JSON response):
#   curl -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"count","arguments":{"to":3}}}' \
#        http://127.0.0.1:8765/mcp
#
# Streaming call (SSE: progress events then the final result):
#   curl -N -H 'Accept: text/event-stream' \
#        -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"count","arguments":{"to":3,"_meta":{"progressToken":"t"}}}}' \
#        http://127.0.0.1:8765/mcp
#
# In your own project the require is `require "mcp"`.
require "../src/mcp"

server = MCP::Server.new(name: "counter", version: "1.0.0")

# `progress` is non-nil only when the client streams (HTTP + Accept:
# text/event-stream + a progressToken). The `try &.` guard makes the tool work
# unchanged over stdio, where progress is always nil.
server.tool("count",
  description: "Counts to N, reporting progress along the way",
  schema: {
    type:       "object",
    properties: {to: {type: "integer", description: "Count up to this number"}},
    required:   ["to"],
  }) do |args, progress|
  n = MCP::Arguments.new(args).int?("to") || 5
  (1..n).each do |i|
    progress.try &.report(progress: i, total: n, message: "step #{i}")
    sleep 200.milliseconds
  end
  "counted to #{n}"
end

http = MCP::Http.new(server, host: "127.0.0.1", port: 8765)
http.on_ready { STDERR.puts "listening on http://127.0.0.1:8765 (POST /mcp, GET /health)" }
# Trap your own signals in a real app; the SDK never traps them.
Signal::INT.trap { http.stop }
http.start
