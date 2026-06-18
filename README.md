<h1 align="center">mcp</h1>

<p align="center">
  <a href="https://github.com/mnemodoc/mcp.cr/actions/workflows/ci.yml"><img src="https://github.com/mnemodoc/mcp.cr/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/mnemodoc/mcp.cr" alt="License: MIT"></a>
  <a href="https://github.com/mnemodoc/mcp.cr/releases"><img src="https://img.shields.io/github/v/release/mnemodoc/mcp.cr" alt="Release"></a>
</p>

<p align="center">
  A batteries-included <a href="https://modelcontextprotocol.io">Model Context Protocol</a>
  <strong>tools</strong> SDK for <a href="https://crystal-lang.org">Crystal</a>.
</p>

Register tools on a server, serve them over **stdio** or **Streamable HTTP**, and
let any MCP client (Claude Code, Cursor, …) discover and call them. The protocol —
JSON-RPC 2.0 framing, the capability handshake, content envelopes, pagination,
progress streaming — is handled for you. You write the tool; the SDK does the rest.

```crystal
require "mcp"

server = MCP::Server.new(name: "demo", version: "1.0.0")

server.tool("greet", description: "Greets someone", schema: {
  type: "object", properties: {name: {type: "string"}}, required: ["name"],
}) do |args, _progress|
  "Hello, #{MCP::Arguments.new(args).require_string("name")}!"
end

MCP::Stdio.new(server).start
```

- **Zero runtime dependencies** — Crystal standard library only.
- **MCP revision [`2025-06-18`](https://modelcontextprotocol.io/specification/2025-06-18)** — `title`/`annotations`/`outputSchema`, structured content, multi-block results, `tools/list` pagination, `ping`, `logging/setLevel`.
- **Two transports** — newline-delimited JSON-RPC over stdio, and Streamable HTTP (synchronous JSON or an SSE stream carrying progress events). The HTTP transport binds a TCP host/port or a UNIX domain socket, and can self-shut-down after an idle period.
- **Ergonomic** — a one-line `server.tool` DSL, typed `MCP::Arguments` accessors, and a rich `MCP::ToolResult` (text / image / audio / resource blocks + machine-readable structured data).

## Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Defining tools](#defining-tools)
- [Reading arguments](#reading-arguments)
- [Returning results](#returning-results)
- [Reporting errors](#reporting-errors)
- [Reporting progress](#reporting-progress)
- [Transports](#transports)
- [What the SDK handles for you](#what-the-sdk-handles-for-you)
- [Connecting a client](#connecting-a-client)
- [API reference](#api-reference)
- [Scope &amp; roadmap](#scope--roadmap)
- [Development](#development)

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  mcp:
    github: mnemodoc/mcp.cr
    version: ~> 1.0
```

Then:

```sh
shards install
```

## Quick start

A server is an `MCP::Server` with one or more registered tools, served through a
transport:

```crystal
require "mcp"

server = MCP::Server.new(name: "weather", version: "1.0.0")

server.tool("get_weather",
  description: "Returns the current weather for a city",
  annotations: MCP::ToolAnnotations.new(read_only_hint: true),
  schema: {
    type:       "object",
    properties: {city: {type: "string", description: "City name"}},
    required:   ["city"],
  }) do |args, _progress|
  city = MCP::Arguments.new(args).require_string("city")
  "It is 22°C and sunny in #{city}."
end

# Serve over stdio (the transport Claude Code speaks).
MCP::Stdio.new(server).start
```

Compile it to a binary (`crystal build weather.cr`) and point your client at the
executable — see [Connecting a client](#connecting-a-client).

## Defining tools

`MCP::Server#tool` registers a tool. Only `name`, `description` and `schema` are
required; `title`, `annotations` and `output_schema` are optional:

```crystal
server.tool("search_docs",
  # Human-readable, shown to the model.
  description: "Full-text search across the indexed documents",

  # Optional display name for UIs (falls back to the tool name).
  title: "Document Search",

  # Behavioural hints (all optional). Clients treat these as untrusted unless
  # the server is trusted — they inform UX, not enforcement.
  annotations: MCP::ToolAnnotations.new(
    read_only_hint: true,    # does not modify its environment
    idempotent_hint: true,   # repeated calls have the same effect
  ),

  # JSON Schema of the arguments. Pass a NamedTuple, a Hash, or a JSON::Any —
  # it is serialised for you.
  schema: {
    type:       "object",
    properties: {
      query: {type: "string", description: "Search terms"},
      limit: {type: "integer", description: "Max results (default 10)"},
    },
    required: ["query"],
  },

  # Optional JSON Schema describing structuredContent (see Returning results).
  output_schema: {
    type:       "object",
    properties: {hits: {type: "array", items: {type: "object"}}},
  }) do |args, progress|
  # … tool body …
  "results"
end
```

The handler block receives `(args : Hash(String, JSON::Any), progress : MCP::Progress?)`
and returns a `String` or an [`MCP::ToolResult`](#returning-results).

### Tool annotations

| Field | Meaning | Default (client-side) |
|---|---|---|
| `title` | Display name | — |
| `read_only_hint` | Does not modify its environment | `false` |
| `destructive_hint` | May perform destructive updates | `true` |
| `idempotent_hint` | Repeated calls have no additional effect | `false` |
| `open_world_hint` | Interacts with an open/external world | `true` |

Only the fields you set are emitted.

## Reading arguments

The handler is handed a raw `Hash(String, JSON::Any)`. Wrap it in `MCP::Arguments`
for typed, opt-in access:

```crystal
server.tool("search_docs", description: "…", schema: { … }) do |args, _progress|
  a = MCP::Arguments.new(args)

  query = a.require_string("query")   # String — raises MCP::ToolError if absent/not a string
  limit = a.int?("limit") || 10       # Int64?  — nil when absent or not an integer
  fuzzy = a.bool?("fuzzy")            # Bool?
  tags  = a.string_array?("tags")     # Array(String)? — nil unless every element is a string

  # …
end
```

| Method | Returns | On missing / wrong type |
|---|---|---|
| `require_string(key)` | `String` | raises `MCP::ToolError` |
| `string?(key)` | `String?` | `nil` |
| `int?(key)` | `Int64?` | `nil` |
| `bool?(key)` | `Bool?` | `nil` |
| `string_array?(key)` | `Array(String)?` | `nil` |
| `raw` | `Hash(String, JSON::Any)` | the underlying hash |

The `?` accessors never raise — a wrong type is treated as absent.

## Returning results

The simplest result is a `String`, auto-wrapped into a single text block:

```crystal
server.tool("ping_tool", description: "…", schema: {type: "object"}) do |_args, _progress|
  "pong"
end
```

For anything richer, return an `MCP::ToolResult`. It carries an ordered list of
**content blocks** and/or a **structured** payload:

```crystal
server.tool("render", description: "…", schema: {type: "object"}) do |_args, _progress|
  MCP::ToolResult.new(content: [
    MCP::TextContent.new("Here is the chart you asked for:").as(MCP::Content),
    MCP::ImageContent.new(data: base64_png, mime_type: "image/png").as(MCP::Content),
  ])
end
```

### Structured content

When a tool returns machine-readable data, put it in `structured_content`. The
SDK also serialises it into a text block automatically (the spec-recommended
fallback for clients that only read text), so you get both surfaces for free:

```crystal
server.tool("stats", description: "…",
  output_schema: {type: "object", properties: {count: {type: "integer"}}},
  schema: {type: "object"}) do |_args, _progress|
  MCP::ToolResult.new(
    structured_content: JSON::Any.new({"count" => JSON::Any.new(42_i64)} of String => JSON::Any),
  )
end
```

Declare an `output_schema` on the tool so clients know the shape. The SDK does
**not** validate `structured_content` against it (that would require a JSON Schema
dependency) — it trusts the tool and publishes the schema for the client to check.

### Content block types

| Block | Constructor | MCP shape |
|---|---|---|
| Text | `MCP::TextContent.new(text)` | `{type: "text", text}` |
| Image | `MCP::ImageContent.new(data, mime_type)` | `{type: "image", data, mimeType}` |
| Audio | `MCP::AudioContent.new(data, mime_type)` | `{type: "audio", data, mimeType}` |
| Resource link | `MCP::ResourceLink.new(uri, name, description:, mime_type:)` | `{type: "resource_link", …}` |
| Embedded resource | `MCP::EmbeddedResource.new(uri, text:, blob:, mime_type:)` | `{type: "resource", resource: {…}}` |

Every block also accepts optional `annotations: MCP::ContentAnnotations.new(audience:, priority:, last_modified:)`.

## Reporting errors

Raise `MCP::ToolError` to signal a business failure. The SDK maps it to a result
with `isError: true` and surfaces your message to the client:

```crystal
server.tool("fetch", description: "…", schema: {type: "object"}) do |args, _progress|
  url = MCP::Arguments.new(args).require_string("url")
  raise MCP::ToolError.new("refusing to fetch a non-https URL") unless url.starts_with?("https://")
  fetch(url)
end
```

Any **other** exception is caught too: it is logged and reported to the client as
a generic `"internal error"` (internals are never leaked). Protocol-level problems
— unknown method, missing tool name — are returned as JSON-RPC errors (`-32601` /
`-32602`) rather than tool errors.

## Reporting progress

Long-running tools can stream progress while they work. The second handler
argument is an `MCP::Progress?` — non-nil only when the client requested streaming
(HTTP with `Accept: text/event-stream` and a `progressToken`):

```crystal
server.tool("reindex", description: "…", schema: {type: "object"}) do |_args, progress|
  total = files.size
  files.each_with_index do |file, i|
    index(file)
    progress.try &.report(progress: i + 1, total: total, message: file)
  end
  "indexed #{total} files"
end
```

`#report(progress:, total: nil, message: nil)` emits a `notifications/progress`
event. A disconnected client is handled silently — reporting never interrupts the
tool. Over stdio (which is request/response) `progress` is always nil, so the
`try &.` guard is all you need.

## Transports

Both transports take the server and expose the same lifecycle:

```crystal
# stdio — newline-delimited JSON-RPC on STDIN/STDOUT (or any IO pair).
transport = MCP::Stdio.new(server)                 # MCP::Stdio.new(server, input, output)

# …or Streamable HTTP — POST /mcp (JSON or SSE) and GET /health.
transport = MCP::Http.new(server, host: "127.0.0.1", port: 8765)

# …or HTTP over a UNIX domain socket instead of TCP (a stale socket file is
# removed before binding), optionally self-shutting-down after an idle span:
transport = MCP::Http.new(server, socket_path: "/run/app/mcp.sock",
                          idle_timeout: 10.minutes)

transport.on_ready    { notify_supervisor_ready }  # after binding / before the read loop
transport.on_stopping { flush_metrics }            # after in-flight requests drain
transport.start                                    # blocks until #stop
```

Call `transport.stop` (e.g. from a signal trap **in your application** — the SDK
never traps signals) for a graceful shutdown: it stops accepting work, lets
in-flight requests finish, fires `on_stopping`, and returns from `start`.

The HTTP transport is **unauthenticated** by design (bind it to loopback, or put
it behind a proxy). CORS is opt-in via `cors_origin:`. Request bodies are capped
at `MCP::Http::MAX_BODY_BYTES` (4 MiB) with a `413` response.

Pass `socket_path:` instead of `host:`/`port:` to bind a UNIX domain socket (any
stale socket file is removed first); pair it with `idle_timeout:` to have the
server unlink the socket, drain in-flight requests, and return from `start` after
that span with no activity — handy for a per-client daemon that a supervisor
re-spawns on demand.

## What the SDK handles for you

You never write JSON-RPC. The shared handler answers, on every transport:

- **`initialize`** — advertises `protocolVersion` `2025-06-18` (echoing the
  client's version when it sends one), `serverInfo`, and capabilities **derived**
  from what you registered (`tools` once a tool exists, plus `logging`).
- **`tools/list`** — paginated with an opaque cursor (`MCP::Handler::PAGE_SIZE`,
  50 per page); each descriptor carries your title / annotations / schemas.
- **`tools/call`** — argument routing, your handler, and the content envelope.
- **`ping`** — liveness.
- **`logging/setLevel`** — maps the RFC 5424 level to the `mcp` log source.
- **`notifications/initialized`** — acknowledged.

## Connecting a client

Build your server to a binary and register it. For **Claude Code** (`stdio`):

```json
{
  "mcpServers": {
    "weather": {
      "command": "/usr/local/bin/weather",
      "args": []
    }
  }
}
```

For an HTTP client, run `MCP::Http.new(server, host:, port:).start` and point the
client at `http://host:port/mcp`.

## API reference

| Type | Purpose |
|---|---|
| `MCP::Server` | Tool registry + dispatch + derived capabilities |
| `MCP::Tool` / `MCP::ToolAnnotations` | A registered tool descriptor and its behavioural hints |
| `MCP::Arguments` | Typed, opt-in accessors over the raw argument hash |
| `MCP::ToolResult` | A tool's result: content blocks + structured content + `is_error?` |
| `MCP::Content` & subtypes | `TextContent`, `ImageContent`, `AudioContent`, `ResourceLink`, `EmbeddedResource`, `ContentAnnotations` |
| `MCP::ToolError` | Raise to return an `isError` result |
| `MCP::Progress` | `#report` progress events from a streaming tool |
| `MCP::Stdio` / `MCP::Http` | Transports (lifecycle callbacks, graceful drain) |
| `MCP::Handler` | The shared JSON-RPC/MCP request handler (used by transports) |
| `MCP::Session` | Per-connection context threaded into the handler |
| `MCP::VERSION` / `MCP::PROTOCOL_VERSION` | `"1.0.0"` / `"2025-06-18"` |

## Scope & roadmap

`mcp` is a **tools** SDK. The following are intentionally **not** in 1.0:

- **Resources** and **prompts**.
- **Server-initiated notifications** — `tools/list_changed`, `notifications/message`, request cancellation.

These need a persistent server→client channel, which the request/response 1.0
does not build. The public API is shaped so they can be added in a
**backward-compatible 1.x**: capabilities are derived (a new feature appears in
the handshake on its own), the handler routes by method (new methods are new
branches), the `MCP::Content` blocks are already shared with resources, and
`MCP::Session` reserves the per-connection seam for push.

There is also no server-side JSON Schema validation of arguments or output — the
schemas are published for the client to enforce, keeping the shard dependency-free.

## Development

```sh
mise dev:deps    # shards install
mise dev:spec    # run the spec suite (Spectator)
mise dev:ameba   # static analysis
mise dev:format  # format src/, spec/ and examples/
mise dev:check   # build-check + ameba + spec
```

Runnable examples live in [`examples/`](examples/). Contributions are welcome —
see [CONTRIBUTING.md](CONTRIBUTING.md) for the guidelines (dependency-free,
test-driven, additive within `1.x`).

## License

[MIT](LICENSE) © Nicolas Rodriguez
