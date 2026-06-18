require "wait_group"

module MCP
  # MCP transport over newline-delimited JSON-RPC 2.0 on an input/output IO pair
  # (STDIN/STDOUT by default; injectable for tests). Each line is dispatched to
  # the shared Handler in a fiber, capped at MAX_CONCURRENT; responses are written
  # under a mutex to prevent interleaving. This transport does not stream, so
  # tools receive a nil progress reporter.
  class Stdio
    Log = ::Log.for("mcp.transport.stdio")

    MAX_CONCURRENT = 32

    def initialize(@server : Server, @input : IO = STDIN, @output : IO = STDOUT)
      @handler = Handler.new(@server)
      @wait_group = WaitGroup.new
      @write_mutex = Mutex.new
      @semaphore = Channel(Nil).new(MAX_CONCURRENT)
      @on_ready = nil.as((-> Nil)?)
      @on_stopping = nil.as((-> Nil)?)
    end

    # Registers a callback invoked once the read loop is ready (e.g. notify the
    # process supervisor).
    def on_ready(&block : -> Nil) : Nil
      @on_ready = block
    end

    # Registers a callback invoked after in-flight requests drain (e.g. notify the
    # process supervisor).
    def on_stopping(&block : -> Nil) : Nil
      @on_stopping = block
    end

    # Reads JSON-RPC messages line by line until EOF. Each message acquires a
    # semaphore slot before spawning (natural backpressure). The WaitGroup is
    # incremented before spawning to avoid a drain race, and decremented in
    # the fiber's ensure block. After EOF, wait blocks until all fibers finish.
    def start : Nil
      Log.info { "stdio transport ready (pid=#{Process.pid})" }
      @on_ready.try(&.call)

      @input.each_line do |line|
        stripped = line.strip
        next if stripped.empty?
        @semaphore.send(nil)
        @wait_group.add(1)
        spawn do
          begin
            process(stripped)
          ensure
            @wait_group.done
            @semaphore.receive
          end
        end
      end
    ensure
      @wait_group.wait
      @on_stopping.try(&.call)
    end

    # Closes the input to break the read loop, triggering a clean shutdown.
    def stop : Nil
      @input.close rescue nil
    end

    # Parses one line, routes to the handler, and writes the response. Parse and
    # handler errors are translated to JSON-RPC error codes.
    private def process(raw : String) : Nil
      request = JSON.parse(raw)
      response = @handler.handle(request)
      write_response(response) if response
    rescue ex : JSON::ParseException
      Log.warn { "invalid JSON: #{ex.message}" }
      write_response(error_response(-32700, "Parse error"))
    rescue ex
      Log.error { "handler error: #{ex.message}" }
      write_response(error_response(-32603, "Internal error"))
    end

    private def error_response(code : Int32, message : String) : Hash(String, JSON::Any)
      err = {"code" => JSON::Any.new(code), "message" => JSON::Any.new(message)} of String => JSON::Any
      {"jsonrpc" => JSON::Any.new("2.0"), "error" => JSON::Any.new(err), "id" => JSON::Any.new(nil)} of String => JSON::Any
    end

    private def write_response(response : Hash(String, JSON::Any)) : Nil
      @write_mutex.synchronize do
        @output.puts(response.to_json)
        @output.flush
      end
    end
  end
end
