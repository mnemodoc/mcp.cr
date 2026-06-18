# Minimal stdio server with a single tool.
#
# Run it, then speak JSON-RPC on stdin:
#
#   printf '%s\n%s\n' \
#     '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
#     '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"greet","arguments":{"name":"Ada"}}}' \
#   | crystal run examples/greet.cr
#
# In your own project the require is `require "mcp"`.
require "../src/mcp"

server = MCP::Server.new(name: "greet-example", version: "1.0.0")

server.tool("greet",
  description: "Greets someone by name",
  annotations: MCP::ToolAnnotations.new(read_only_hint: true),
  schema: {
    type:       "object",
    properties: {name: {type: "string", description: "Who to greet"}},
    required:   ["name"],
  }) do |args, _progress|
  name = MCP::Arguments.new(args).require_string("name")
  "Hello, #{name}!"
end

MCP::Stdio.new(server).start
