# A small calculator server showing structured content + outputSchema,
# behavioural annotations, typed arguments, and MCP::ToolError.
#
#   printf '%s\n%s\n' \
#     '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
#     '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"add","arguments":{"a":2,"b":40}}}' \
#   | crystal run examples/calculator.cr
#
# In your own project the require is `require "mcp"`.
require "../src/mcp"

server = MCP::Server.new(name: "calculator", version: "1.0.0")

# Returns its result as structuredContent (machine-readable). The SDK also
# serialises it into a text block automatically, so text-only clients still work.
server.tool("add",
  description: "Adds two integers",
  annotations: MCP::ToolAnnotations.new(read_only_hint: true, idempotent_hint: true),
  output_schema: {type: "object", properties: {sum: {type: "integer"}}},
  schema: {
    type:       "object",
    properties: {a: {type: "integer"}, b: {type: "integer"}},
    required:   ["a", "b"],
  }) do |args, _progress|
  a = MCP::Arguments.new(args)
  x = a.int?("a") || raise MCP::ToolError.new("a must be an integer")
  y = a.int?("b") || raise MCP::ToolError.new("b must be an integer")
  MCP::ToolResult.new(
    structured_content: JSON::Any.new({"sum" => JSON::Any.new(x + y)} of String => JSON::Any),
  )
end

# Demonstrates a business error surfaced to the client as isError.
server.tool("divide",
  description: "Integer division of a by b",
  schema: {
    type:       "object",
    properties: {a: {type: "integer"}, b: {type: "integer"}},
    required:   ["a", "b"],
  }) do |args, _progress|
  a = MCP::Arguments.new(args)
  x = a.int?("a") || raise MCP::ToolError.new("a must be an integer")
  y = a.int?("b") || raise MCP::ToolError.new("b must be an integer")
  raise MCP::ToolError.new("division by zero") if y == 0
  "#{x // y}"
end

MCP::Stdio.new(server).start
