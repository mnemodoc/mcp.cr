# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] — 2026-06-18

Initial release: a batteries-included MCP **tools** SDK for Crystal, targeting
MCP protocol revision `2025-06-18`. Zero runtime dependencies beyond the Crystal
standard library.

### Added

- **`MCP::Server`** — tool registry, dispatch, and capabilities derived from what
  is registered.
- **`MCP::Server#tool`** — register a tool with a name, description, JSON Schema,
  and optional `title`, `annotations`, and `output_schema`. Handlers return a
  `String` (auto-wrapped as text) or an `MCP::ToolResult`.
- **`MCP::ToolResult`** — content blocks plus optional `structured_content`, with
  a spec-recommended text fallback synthesised automatically.
- **Content blocks** — `MCP::TextContent`, `ImageContent`, `AudioContent`,
  `ResourceLink`, `EmbeddedResource`, each with optional `ContentAnnotations`.
- **`MCP::ToolAnnotations`** — `read_only_hint` / `destructive_hint` /
  `idempotent_hint` / `open_world_hint` / `title`.
- **`MCP::Arguments`** — typed, opt-in accessors over the raw argument hash
  (`require_string`, `string?`, `int?`, `bool?`, `string_array?`).
- **`MCP::ToolError`** — raise to return an `isError` result with your message.
- **`MCP::Progress`** — stream `notifications/progress` events from long-running
  tools.
- **`MCP::Handler`** — shared JSON-RPC 2.0 / MCP handler: `initialize` (with
  protocol-version echo), `tools/list` (opaque-cursor pagination, 50 per page),
  `tools/call`, `ping`, and `logging/setLevel`.
- **Transports** — `MCP::Stdio` (newline-delimited JSON-RPC) and `MCP::Http`
  (Streamable HTTP: synchronous JSON or an SSE stream), each with
  `on_ready`/`on_stopping` callbacks, graceful in-flight draining, and `stop`.
  The HTTP transport caps request bodies at 4 MiB, offers opt-in CORS, binds
  either a TCP host/port or a UNIX domain socket (`socket_path:`, stale file
  removed before binding), and can self-shut-down after an `idle_timeout:` span.
- **`MCP::Session`** — per-connection context threaded into the handler; the
  reserved seam for future server-initiated notifications.

[Unreleased]: https://github.com/mnemodoc/mcp.cr/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/mnemodoc/mcp.cr/releases/tag/v1.0.0
