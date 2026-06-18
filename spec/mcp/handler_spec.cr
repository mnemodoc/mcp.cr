# spec/mcp/handler_spec.cr
require "../spec_helper"

Spectator.describe MCP::Handler do
  def build_server : MCP::Server
    server = MCP::Server.new(name: "test-server", version: "9.9.9")
    server.tool("echo", description: "Echoes", schema: {type: "object"}) do |args, _p|
      args["msg"]?.try(&.as_s) || "empty"
    end
    server.tool("boom", description: "Fails", schema: {type: "object"}) do |_a, _p|
      raise MCP::ToolError.new("kaboom")
    end
    server
  end

  let(handler) { MCP::Handler.new(build_server) }

  it "returns protocolVersion and serverInfo on initialize" do
    req = JSON.parse(%({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}))
    # ameba:disable Lint/NotNil
    result = handler.handle(req).not_nil!["result"]
    expect(result["protocolVersion"].as_s).to eq(MCP::PROTOCOL_VERSION)
    expect(result["serverInfo"]["name"].as_s).to eq("test-server")
    expect(result["capabilities"].as_h.has_key?("tools")).to be_true
  end

  it "advertises the 2025-06-18 protocol revision" do
    req = JSON.parse(%({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}))
    # ameba:disable Lint/NotNil
    result = handler.handle(req).not_nil!["result"]
    expect(result["protocolVersion"].as_s).to eq("2025-06-18")
  end

  it "echoes the client's protocolVersion when provided" do
    req = JSON.parse(%({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}))
    # ameba:disable Lint/NotNil
    result = handler.handle(req).not_nil!["result"]
    expect(result["protocolVersion"].as_s).to eq("2025-03-26")
  end

  it "lists registered tools" do
    req = JSON.parse(%({"jsonrpc":"2.0","id":2,"method":"tools/list"}))
    # ameba:disable Lint/NotNil
    tools = handler.handle(req).not_nil!["result"]["tools"].as_a
    expect(tools.map(&.["name"].as_s)).to contain("echo")
  end

  it "wraps a successful tool call as text content with isError false" do
    req = JSON.parse(%({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"msg":"hi"}}}))
    # ameba:disable Lint/NotNil
    result = handler.handle(req).not_nil!["result"]
    expect(result["isError"].as_bool).to be_false
    expect(result["content"].as_a.first["text"].as_s).to eq("hi")
  end

  it "sets isError true when the tool raises ToolError" do
    req = JSON.parse(%({"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"boom","arguments":{}}}))
    # ameba:disable Lint/NotNil
    result = handler.handle(req).not_nil!["result"]
    expect(result["isError"].as_bool).to be_true
    expect(result["content"].as_a.first["text"].as_s).to eq("kaboom")
  end

  it "sets isError true for an unregistered tool" do
    req = JSON.parse(%({"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"ghost","arguments":{}}}))
    # ameba:disable Lint/NotNil
    expect(handler.handle(req).not_nil!["result"]["isError"].as_bool).to be_true
  end

  it "returns -32602 when the tool name is missing" do
    req = JSON.parse(%({"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"arguments":{}}}))
    # ameba:disable Lint/NotNil
    expect(handler.handle(req).not_nil!["error"]["code"].as_i).to eq(-32602)
  end

  it "returns -32601 for an unknown method" do
    req = JSON.parse(%({"jsonrpc":"2.0","id":7,"method":"nope/nope"}))
    # ameba:disable Lint/NotNil
    expect(handler.handle(req).not_nil!["error"]["code"].as_i).to eq(-32601)
  end

  it "returns nil for notifications/initialized" do
    req = JSON.parse(%({"jsonrpc":"2.0","method":"notifications/initialized"}))
    expect(handler.handle(req)).to be_nil
  end

  it "emits structuredContent when a tool returns a ToolResult" do
    server = MCP::Server.new(name: "test-server", version: "9.9.9")
    server.tool("data", description: "Data", schema: {type: "object"}) do |_a, _p|
      MCP::ToolResult.new(structured_content: JSON.parse(%({"n":42})))
    end
    handler = MCP::Handler.new(server)
    req = JSON.parse(%({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"data","arguments":{}}}))
    # ameba:disable Lint/NotNil
    result = handler.handle(req).not_nil!["result"]
    expect(result["structuredContent"]["n"].as_i).to eq(42)
    expect(result["isError"].as_bool).to be_false
  end

  it "streams the final result frame and closes the channel" do
    channel = Channel(JSON::Any).new(8)
    session = MCP::Session.new(channel: channel, progress_token: JSON::Any.new("tok"), request_id: JSON::Any.new(1_i64))
    req = JSON.parse(%({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{"msg":"hi"}}}))
    expect(handler.handle(req, session)).to be_nil
    frames = [] of JSON::Any
    while frame = channel.receive?
      frames << frame
    end
    expect(frames.size).to eq(1)
    expect(frames.first["result"]["isError"].as_bool).to be_false
  end

  it "answers ping with an empty result" do
    req = JSON.parse(%({"jsonrpc":"2.0","id":9,"method":"ping"}))
    # ameba:disable Lint/NotNil
    result = handler.handle(req).not_nil!["result"]
    expect(result.as_h.empty?).to be_true
  end

  it "advertises the logging capability on initialize" do
    req = JSON.parse(%({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}))
    # ameba:disable Lint/NotNil
    capabilities = handler.handle(req).not_nil!["result"]["capabilities"]
    expect(capabilities.as_h.has_key?("logging")).to be_true
  end

  it "accepts logging/setLevel and returns an empty result" do
    req = JSON.parse(%({"jsonrpc":"2.0","id":10,"method":"logging/setLevel","params":{"level":"debug"}}))
    # ameba:disable Lint/NotNil
    result = handler.handle(req).not_nil!["result"]
    expect(result.as_h.empty?).to be_true
    expect(MCP::Log.level).to eq(::Log::Severity::Debug)
  end

  it "rejects an invalid logging level with -32602" do
    req = JSON.parse(%({"jsonrpc":"2.0","id":11,"method":"logging/setLevel","params":{"level":"bogus"}}))
    # ameba:disable Lint/NotNil
    expect(handler.handle(req).not_nil!["error"]["code"].as_i).to eq(-32602)
  end

  after_each { MCP::Log.level = ::Log::Severity::Info }

  describe "tools/list pagination" do
    def build_many : MCP::Handler
      server = MCP::Server.new(name: "many", version: "1.0.0")
      51.times do |i|
        server.tool("tool_#{i}", description: "d", schema: {type: "object"}) { |_a, _p| "x" }
      end
      MCP::Handler.new(server)
    end

    it "returns the first page with a nextCursor when tools exceed the page size" do
      req = JSON.parse(%({"jsonrpc":"2.0","id":1,"method":"tools/list"}))
      # ameba:disable Lint/NotNil
      result = build_many.handle(req).not_nil!["result"]
      expect(result["tools"].as_a.size).to eq(50)
      expect(result["nextCursor"].as_s.empty?).to be_false
    end

    it "returns the remainder and no nextCursor on the last page" do
      handler = build_many
      # ameba:disable Lint/NotNil
      first = handler.handle(JSON.parse(%({"jsonrpc":"2.0","id":1,"method":"tools/list"}))).not_nil!["result"]
      cursor = first["nextCursor"].as_s
      req = JSON.parse(%({"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"cursor":"#{cursor}"}}))
      # ameba:disable Lint/NotNil
      result = handler.handle(req).not_nil!["result"]
      expect(result["tools"].as_a.size).to eq(1)
      expect(result.as_h.has_key?("nextCursor")).to be_false
    end
  end
end
