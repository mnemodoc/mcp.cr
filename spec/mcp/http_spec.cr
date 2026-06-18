# spec/mcp/http_spec.cr
require "../spec_helper"
require "http/client"

Spectator.describe MCP::Http do
  def build_server : MCP::Server
    server = MCP::Server.new(name: "test-server", version: "9.9.9")
    server.tool("echo", description: "Echoes", schema: {type: "object"}) do |args, _p|
      args["msg"]?.try(&.as_s) || "empty"
    end
    server.tool("count", description: "Counts", schema: {type: "object"}) do |_a, progress|
      progress.try &.report(progress: 1, total: 2, message: "one")
      progress.try &.report(progress: 2, total: 2, message: "two")
      "counted"
    end
    server
  end

  it "answers GET /health" do
    transport = MCP::Http.new(build_server, host: "127.0.0.1", port: 9911)
    spawn { transport.start }
    sleep 50.milliseconds
    begin
      response = HTTP::Client.get("http://127.0.0.1:9911/health")
      expect(JSON.parse(response.body)["status"].as_s).to eq("ok")
    ensure
      transport.stop
    end
  end

  it "returns a synchronous JSON response for a normal POST /mcp" do
    transport = MCP::Http.new(build_server, host: "127.0.0.1", port: 9912)
    spawn { transport.start }
    sleep 50.milliseconds
    begin
      body = %({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{"msg":"hi"}}})
      response = HTTP::Client.post("http://127.0.0.1:9912/mcp", body: body)
      expect(JSON.parse(response.body)["result"]["content"].as_a.first["text"].as_s).to eq("hi")
    ensure
      transport.stop
    end
  end

  it "streams SSE progress frames then the final result when Accept is text/event-stream" do
    transport = MCP::Http.new(build_server, host: "127.0.0.1", port: 9913)
    spawn { transport.start }
    sleep 50.milliseconds
    begin
      body = %({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"count","arguments":{"_meta":{"progressToken":"tok"}}}})
      headers = HTTP::Headers{"Accept" => "text/event-stream"}
      response = HTTP::Client.post("http://127.0.0.1:9913/mcp", headers: headers, body: body)
      # ameba:disable Naming/BlockParameterName
      frames = response.body.scan(/data: ([^\n]+)/).map { |m| JSON.parse(m[1].strip) }
      # ameba:disable Naming/BlockParameterName
      progress_frames = frames.select { |f| f["method"]?.try(&.as_s) == "notifications/progress" }
      # ameba:disable Naming/BlockParameterName
      final = frames.find { |f| f["result"]? }
      expect(progress_frames.size).to eq(2)
      # ameba:disable Lint/NotNil
      expect(final.not_nil!["result"]["content"].as_a.first["text"].as_s).to eq("counted")
    ensure
      transport.stop
    end
  end

  it "answers a non-streaming method over SSE with a single data frame" do
    transport = MCP::Http.new(build_server, host: "127.0.0.1", port: 9915)
    spawn { transport.start }
    sleep 50.milliseconds
    begin
      headers = HTTP::Headers{"Accept" => "text/event-stream"}
      body = %({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}})
      response = HTTP::Client.post("http://127.0.0.1:9915/mcp", headers: headers, body: body)
      # ameba:disable Naming/BlockParameterName
      frames = response.body.scan(/data: ([^\n]+)/).map { |m| JSON.parse(m[1].strip) }
      expect(frames.size).to eq(1)
      expect(frames.first["result"]["protocolVersion"].as_s).to eq("2025-06-18")
    ensure
      transport.stop
    end
  end

  it "rejects an oversized POST body with 413" do
    transport = MCP::Http.new(build_server, host: "127.0.0.1", port: 9914)
    spawn { transport.start }
    sleep 50.milliseconds
    begin
      # Use a raw socket to send only headers with an oversized Content-Length.
      # This triggers the pre-check rejection before any body is written, letting
      # the client read the 413 response cleanly without a broken-pipe race.
      fake_length = MCP::Http::MAX_BODY_BYTES + 1
      raw = TCPSocket.new("127.0.0.1", 9914)
      raw.print("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:9914\r\nContent-Type: application/json\r\nContent-Length: #{fake_length}\r\n\r\n")
      raw.flush
      status_line = raw.gets
      raw.close
      expect(status_line).to contain("413")
    ensure
      transport.stop
    end
  end
end
