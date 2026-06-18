# Examples

Runnable example servers built with `mcp`. Each one requires the library via
`require "../src/mcp"` so it runs straight from this repo — in your own project
the require is simply `require "mcp"`.

| Example | Transport | Shows |
|---|---|---|
| [`greet.cr`](greet.cr) | stdio | the minimal server: one tool, `MCP::Arguments`, a `String` result |
| [`calculator.cr`](calculator.cr) | stdio | `structuredContent` + `outputSchema`, annotations, `MCP::ToolError` |
| [`streaming_http.cr`](streaming_http.cr) | Streamable HTTP | progress streaming over SSE, `/health`, graceful `stop` |

## Running

```sh
# stdio examples speak JSON-RPC on stdin/stdout:
printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | crystal run examples/greet.cr

# the HTTP example listens on 127.0.0.1:8765:
crystal run examples/streaming_http.cr
curl http://127.0.0.1:8765/health
```

Each file's header comment has copy-pasteable `tools/call` invocations.
