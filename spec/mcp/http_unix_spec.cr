# spec/mcp/http_unix_spec.cr
require "../spec_helper"
require "http/client"
require "socket"

Spectator.describe "MCP::Http UNIX socket" do
  def build_server : MCP::Server
    MCP::Server.new(name: "test", version: "0.0.0")
  end

  it "handles a JSON-RPC round-trip over a UNIX socket" do
    path = "/tmp/mcp-test-unix-roundtrip-#{Process.pid}.sock"
    transport = MCP::Http.new(build_server, socket_path: path)
    ready = Channel(Nil).new(1)
    transport.on_ready { ready.send(nil) }

    spawn { transport.start }
    ready.receive

    begin
      sock = UNIXSocket.new(path)
      client = HTTP::Client.new(sock)
      body = %({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}})
      response = client.post("/mcp", body: body)
      parsed = JSON.parse(response.body)
      expect(parsed["result"]["protocolVersion"].as_s).to eq("2025-06-18")
    ensure
      transport.stop
      File.delete?(path)
    end
  end

  it "shuts down after the idle timeout and removes the socket file" do
    path = "/tmp/mcp-test-unix-idle-#{Process.pid}.sock"
    transport = MCP::Http.new(build_server, socket_path: path, idle_timeout: 200.milliseconds)
    ready = Channel(Nil).new(1)
    transport.on_ready { ready.send(nil) }

    done = Channel(Nil).new(1)
    spawn do
      transport.start
      done.send(nil)
    end
    ready.receive

    # No requests — let the reaper fire. Allow up to 2 seconds.
    select
    when done.receive
      # expected: server exited on its own
    when timeout(2.seconds)
      transport.stop
      fail "server did not idle-shutdown within 2 seconds"
    end

    expect(File.exists?(path)).to be_false
  end
end
