require "http/server"
require "wait_group"

module MCP
  # MCP transport over Streamable HTTP. Routes:
  #   POST /mcp    — JSON-RPC 2.0; returns a JSON body, or an SSE stream when the
  #                  client sends Accept: text/event-stream (progress events
  #                  followed by the final result frame).
  #   GET  /health — liveness probe.
  # CORS is opt-in via cors_origin (unset by default; this transport is unauthenticated).
  # When socket_path is set, binds a UNIX domain socket instead of TCP. When
  # idle_timeout is set, the server shuts itself down after that span of
  # inactivity (no requests in flight and no new request arriving).
  class Http
    Log = ::Log.for("mcp.transport.http")

    # Maximum accepted POST body size. The transport is unauthenticated, so an
    # unbounded read is a memory/DoS vector. 4 MiB comfortably covers any MCP
    # JSON-RPC request while capping abuse.
    MAX_BODY_BYTES = 4 * 1024 * 1024

    # Constructs an HTTP transport. Pass either host+port (TCP) or socket_path
    # (UNIX domain socket). When idle_timeout is set, the server stops itself
    # after that span with no in-flight requests.
    def initialize(
      @server : Server,
      *,
      host : String = "",
      port : Int32 = 0,
      socket_path : String? = nil,
      idle_timeout : Time::Span? = nil,
      cors_origin : String? = nil
    )
      @host = host
      @port = port
      @socket_path = socket_path
      @idle_timeout = idle_timeout
      @cors_origin = cors_origin
      @handler = Handler.new(@server)
      @http_server = nil.as(HTTP::Server?)
      @wait_group = WaitGroup.new
      @on_ready = nil.as((-> Nil)?)
      @on_stopping = nil.as((-> Nil)?)
      @inflight = Atomic(Int32).new(0)
      @last_activity = Time.monotonic
    end

    def on_ready(&block : -> Nil) : Nil
      @on_ready = block
    end

    def on_stopping(&block : -> Nil) : Nil
      @on_stopping = block
    end

    # Binds and listens. After listen returns (via stop), the server no longer
    # accepts new connections, so no new add can race with wait. Drains in-flight
    # requests via WaitGroup before invoking the stopping callback.
    # When socket_path is set, binds a UNIX domain socket (removing any stale
    # socket file first). When idle_timeout is set, spawns a reaper fiber that
    # calls stop after the configured idle span.
    def start : Nil
      server = HTTP::Server.new do |ctx|
        @wait_group.add(1)
        @inflight.add(1)
        @last_activity = Time.monotonic
        begin
          handle(ctx)
        rescue ex : IO::Error
          raise ex unless ex.os_error.try(&.in?(Errno::EPIPE, Errno::ECONNRESET))
        ensure
          @inflight.sub(1)
          @wait_group.done
        end
      end
      @http_server = server

      if sp = @socket_path
        File.delete?(sp)
        server.bind_unix(sp)
        Log.info { "HTTP transport listening on unix://#{sp}" }
      else
        addr = server.bind_tcp(@host, @port)
        Log.info { "HTTP transport listening on http://#{addr}" }
      end

      if timeout = @idle_timeout
        spawn { run_idle_reaper(timeout) }
      end

      @on_ready.try(&.call)
      server.listen

      @wait_group.wait
      @on_stopping.try(&.call)
    ensure
      @http_server = nil
    end

    def stop : Nil
      @http_server.try(&.close)
    end

    # Polls periodically and shuts the server down once it has been idle
    # (no in-flight requests) for at least idle_timeout. Removes the UNIX
    # socket file before stopping so no new connections can be accepted
    # after the decision to shut down.
    private def run_idle_reaper(idle_timeout : Time::Span) : Nil
      check_interval = {idle_timeout, 30.seconds}.min
      loop do
        sleep check_interval
        next if @inflight.get > 0
        next if (Time.monotonic - @last_activity) < idle_timeout

        # Remove the socket file first so no new connection arrives
        # between the idle decision and the accept loop stopping.
        if sp = @socket_path
          File.delete?(sp)
        end

        # Drain any connection that slipped in just before the unlink.
        until @inflight.get == 0
          sleep 1.millisecond
        end

        stop
        break
      end
    end

    private def handle(ctx : HTTP::Server::Context) : Nil
      req = ctx.request
      res = ctx.response
      if origin = @cors_origin
        res.headers["Access-Control-Allow-Origin"] = origin
      end

      case {req.method, req.path}
      when {"POST", "/mcp"}
        handle_mcp(req, res)
      when {"GET", "/health"}
        res.content_type = "application/json"
        res.print({"status" => "ok", "version" => @server.version}.to_json)
      else
        res.status = HTTP::Status::NOT_FOUND
        res.content_type = "application/json"
        res.print({"error" => "not found"}.to_json)
      end
    end

    # Routes POST /mcp to streaming or synchronous handling based on Accept.
    private def handle_mcp(req : HTTP::Request, res : HTTP::Server::Response) : Nil
      if (len = req.content_length) && len > MAX_BODY_BYTES
        return reject_too_large(res)
      end
      body = read_bounded(req.body)
      return reject_too_large(res) if body.nil?
      request = JSON.parse(body)

      if req.headers["Accept"]?.try(&.includes?("text/event-stream"))
        handle_streaming(request, res)
      else
        id = request["id"]? || JSON::Any.new(nil)
        begin
          response = @handler.handle(request)
          res.content_type = "application/json"
          res.print((response || empty_ack).to_json)
        rescue ex
          Log.error { "Unhandled exception in sync handler: #{ex.message}" }
          err = {"code" => JSON::Any.new(-32603), "message" => JSON::Any.new(ex.message || "internal error")} of String => JSON::Any
          frame = {"jsonrpc" => JSON::Any.new("2.0"), "id" => id, "error" => JSON::Any.new(err)} of String => JSON::Any
          res.content_type = "application/json"
          res.print(frame.to_json)
        end
      end
    rescue ex : JSON::ParseException
      res.status = HTTP::Status::BAD_REQUEST
      res.content_type = "application/json"
      res.print({"error" => "invalid JSON"}.to_json)
    end

    # Spawns a writer fiber that turns channel events into SSE frames, then runs
    # the handler (which closes the channel after the final frame). Waits for the
    # writer to drain before returning.
    private def handle_streaming(request : JSON::Any, res : HTTP::Server::Response) : Nil
      channel = Channel(JSON::Any).new(32)
      token = request.dig?("params", "arguments", "_meta", "progressToken") || JSON::Any.new(nil)
      id = request["id"]? || JSON::Any.new(nil)
      session = Session.new(channel: channel, progress_token: token, request_id: id)

      res.content_type = "text/event-stream"
      res.headers["Cache-Control"] = "no-cache"
      res.headers["X-Accel-Buffering"] = "no"

      done = Channel(Nil).new(1)
      spawn do
        loop do
          event = channel.receive?
          break if event.nil?
          res.print("data: #{event.to_json}\n\n")
          res.flush
        rescue ex : IO::Error
          break
        end
        done.send(nil)
      end

      begin
        emit_sync_response(@handler.handle(request, session), channel)
      rescue ex
        err = {"code" => JSON::Any.new(-32603), "message" => JSON::Any.new(ex.message || "internal error")} of String => JSON::Any
        frame = JSON::Any.new({"jsonrpc" => JSON::Any.new("2.0"), "id" => id, "error" => JSON::Any.new(err)} of String => JSON::Any)
        channel.send(frame) rescue Channel::ClosedError
      ensure
        channel.close rescue Channel::ClosedError
      end

      done.receive
    end

    # Emits a synchronous handler response as one SSE data frame. tools/call
    # streams its own result and returns nil here, so a nil response sends
    # nothing; any other method's response hash is forwarded as a single frame
    # so a client that requested text/event-stream still receives its answer.
    private def emit_sync_response(response : Hash(String, JSON::Any)?, channel : Channel(JSON::Any)) : Nil
      return unless response
      channel.send(JSON::Any.new(response)) rescue Channel::ClosedError
    end

    # Reads at most MAX_BODY_BYTES from the body; returns nil when the source
    # carries more (truncation detected by reading one extra byte).
    private def read_bounded(body : IO?) : String?
      return "" unless body
      mem = IO::Memory.new
      copied = IO.copy(body, mem, MAX_BODY_BYTES + 1)
      return nil if copied > MAX_BODY_BYTES
      mem.to_s
    end

    private def reject_too_large(res : HTTP::Server::Response) : Nil
      res.status = HTTP::Status::PAYLOAD_TOO_LARGE
      res.content_type = "application/json"
      res.print({"error" => "request body too large"}.to_json)
    end

    private def empty_ack : Hash(String, JSON::Any)
      {"jsonrpc" => JSON::Any.new("2.0")} of String => JSON::Any
    end
  end
end
