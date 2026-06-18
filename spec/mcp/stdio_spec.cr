# spec/mcp/stdio_spec.cr
require "../spec_helper"

Spectator.describe MCP::Stdio do
  def build_server : MCP::Server
    server = MCP::Server.new(name: "test-server", version: "9.9.9")
    server.tool("echo", description: "Echoes", schema: {type: "object"}) do |args, _p|
      args["msg"]?.try(&.as_s) || "empty"
    end
    server
  end

  it "reads a request line and writes a JSON-RPC response line" do
    input = IO::Memory.new(%({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{"msg":"hi"}}}) + "\n")
    output = IO::Memory.new
    ready = false
    stdio = MCP::Stdio.new(build_server, input: input, output: output)
    stdio.on_ready { ready = true }
    stdio.start
    response = JSON.parse(output.to_s.lines.first)
    expect(ready).to be_true
    expect(response["result"]["content"].as_a.first["text"].as_s).to eq("hi")
  end

  it "skips blank lines and writes a parse error for invalid JSON" do
    input = IO::Memory.new("\n{ not json\n")
    output = IO::Memory.new
    MCP::Stdio.new(build_server, input: input, output: output).start
    response = JSON.parse(output.to_s.lines.first)
    expect(response["error"]["code"].as_i).to eq(-32700)
  end

  it "invokes the stopping callback after the input is exhausted" do
    stopped = false
    stdio = MCP::Stdio.new(build_server, input: IO::Memory.new(""), output: IO::Memory.new)
    stdio.on_stopping { stopped = true }
    stdio.start
    expect(stopped).to be_true
  end
end
