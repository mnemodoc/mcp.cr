# CLAUDE.md

Guidance for Claude Code (and other agents) working in this repository.

## What this is

`mcp` is a self-contained **Model Context Protocol tools SDK** for Crystal,
targeting MCP revision `2025-06-18`. It implements JSON-RPC 2.0 framing, the
capability handshake, a tool registry, the `tools/*` surface, and two transports
(stdio + Streamable HTTP). It has **no runtime dependencies** — Crystal standard
library only.

## Working agreements

- **Memory is not a source.** Do not act or assert from training memory or prior
  context. Anything not read from a file or a cited spec in the current turn is
  off-limits as the basis for a change. When unsure, read first or say so.
- Comments go **above** the code, never inline (including `# ameba:disable`
  directives — place them on their own line above the offending line).
- Code, comments, and test descriptions are in **English**.
- Named arguments on non-trivial calls.
- **After any code change, run the full `mise dev:check`** (build-check + ameba +
  spec). Never rely on a single sub-task.

## Hard constraints

- **Zero runtime dependencies.** stdlib only (`json`, `log`, `http`, `socket`).
  Never add a runtime shard.
- `MCP::PROTOCOL_VERSION = "2025-06-18"`, `MCP::VERSION` follows SemVer.
- **Error model:** a tool **raises** `MCP::ToolError` (or any exception) to signal
  failure ⇒ the handler returns an `isError` result. A tool never returns an
  `{"error" => …}` map. Protocol problems (unknown method, missing tool name) are
  JSON-RPC errors (`-32601` / `-32602`).
- Keep the public API **additive** within `1.x` (this is published): new
  capabilities flow through the existing seams (derived capabilities, the
  handler's `case` router, shared `MCP::Content` blocks, `MCP::Session`) without
  breaking the `1.0` surface. Breaking changes wait for `2.0`.
- No server-side JSON Schema validation (it would require a dependency); schemas
  are published for the client to enforce.

## Development commands

```sh
mise dev:deps    # shards install
mise dev:spec    # run specs (Spectator)
mise dev:ameba   # static analysis
mise dev:format  # format src/, spec/, examples/
mise dev:check   # build-check + ameba + spec
mise dev:build   # compile-check the library (no codegen)
```

Run a single spec file: `crystal spec spec/mcp/handler_spec.cr`.

## Architecture

```
src/mcp.cr                     Entrypoint: requires + MCP::VERSION / PROTOCOL_VERSION / Log
src/mcp/
  errors.cr                    MCP::ToolError
  tool.cr                      MCP::Tool (descriptor, memoised #to_definition)
  tool_annotations.cr          MCP::ToolAnnotations (behavioural hints)
  content.cr                   MCP::Content + Text/Image/Audio/ResourceLink/EmbeddedResource + ContentAnnotations
  tool_result.cr               MCP::ToolResult (content blocks + structuredContent + isError)
  arguments.cr                 MCP::Arguments (typed accessors over the raw arg hash)
  progress.cr                  MCP::Progress (notifications/progress reporter)
  session.cr                   MCP::Session (per-connection context; Family-2 push seam)
  server.cr                    MCP::Server (tool registry, dispatch, capabilities)
  handler.cr                   MCP::Handler (JSON-RPC 2.0 + MCP routing: initialize/tools/ping/logging/pagination)
  transport/
    stdio.cr                   MCP::Stdio (newline-delimited JSON-RPC; WaitGroup drain)
    http.cr                    MCP::Http (Streamable HTTP: JSON or SSE; bounded body; opt-in CORS; TCP or UNIX socket bind; idle self-shutdown)
```

Specs mirror the source under `spec/mcp/`. Runnable example servers live in
`examples/`.

## Out of scope for 1.0

Resources, prompts, and server-initiated notifications (`tools/list_changed`,
`notifications/message`, cancellation). These need a persistent server→client
channel that 1.0 does not build; `MCP::Session` reserves the seam.
