module MCP
  # Pure JSON-RPC 2.0 / MCP request handler shared by all transports. Maps a
  # parsed request to a response hash; transports own framing and IO. When a
  # Session with a channel is provided for a tools/call, the final result is sent
  # on the channel (which is then closed) and #handle returns nil.
  class Handler
    # MCP (RFC 5424) log level names mapped to Crystal severities. Crystal has no
    # Critical level, so critical/alert/emergency fold onto Fatal.
    SEVERITY_BY_LEVEL = {
      "debug"     => ::Log::Severity::Debug,
      "info"      => ::Log::Severity::Info,
      "notice"    => ::Log::Severity::Notice,
      "warning"   => ::Log::Severity::Warn,
      "error"     => ::Log::Severity::Error,
      "critical"  => ::Log::Severity::Fatal,
      "alert"     => ::Log::Severity::Fatal,
      "emergency" => ::Log::Severity::Fatal,
    }

    # Maximum number of tools returned per tools/list page.
    PAGE_SIZE = 50

    def initialize(@server : Server)
    end

    # Handles one request. Returns the response hash, or nil for notifications
    # and for streaming tool calls (response delivered on the session channel).
    def handle(request : JSON::Any, session : Session? = nil) : Hash(String, JSON::Any)?
      id = request["id"]?
      method = request["method"]?.try(&.as_s?) || ""
      case method
      when "initialize"
        success_response(id, initialize_result(request))
      when "tools/list"
        success_response(id, tools_list_result(request))
      when "tools/call"
        handle_tools_call(id, request, session)
      when "ping"
        success_response(id, {} of String => JSON::Any)
      when "logging/setLevel"
        handle_set_level(id, request)
      when "notifications/initialized"
        nil
      else
        error_response(id, -32601, "Method not found: #{method}")
      end
    end

    # Builds the initialize result. Echoes the client's protocolVersion when it
    # sends one, otherwise advertises the version this server implements.
    private def initialize_result(request : JSON::Any) : Hash(String, JSON::Any)
      client_version = request.dig?("params", "protocolVersion").try(&.as_s?)
      capabilities = @server.capabilities
      capabilities["logging"] = JSON::Any.new({} of String => JSON::Any)
      {
        "protocolVersion" => JSON::Any.new(client_version || PROTOCOL_VERSION),
        "serverInfo"      => JSON::Any.new({
          "name"    => JSON::Any.new(@server.name),
          "version" => JSON::Any.new(@server.version),
        } of String => JSON::Any),
        "capabilities" => JSON::Any.new(capabilities),
      } of String => JSON::Any
    end

    # Applies a client-requested minimum log level to the MCP log source. Returns
    # an empty result, or a -32602 error for an unknown level name.
    private def handle_set_level(id : JSON::Any?, request : JSON::Any) : Hash(String, JSON::Any)
      level = request.dig?("params", "level").try(&.as_s?)
      severity = level.try { |name| SEVERITY_BY_LEVEL[name]? }
      return error_response(id, -32602, "invalid log level: #{level}") unless severity
      Log.level = severity
      success_response(id, {} of String => JSON::Any)
    end

    # Builds the tools/list result for one page. The cursor is an opaque decimal
    # offset; nextCursor is the offset of the following page, present only when
    # more tools remain. An absent or malformed cursor starts at offset 0.
    # The offset cursor is stable only because the tool registry is immutable
    # after startup. A future mutable registry (with tools/list_changed) must
    # revisit the cursor encoding so it can detect a stale page.
    private def tools_list_result(request : JSON::Any) : Hash(String, JSON::Any)
      all = @server.tool_definitions
      offset = request.dig?("params", "cursor").try(&.as_s?).try(&.to_i?) || 0
      offset = 0 if offset < 0
      page = all[offset, PAGE_SIZE]? || [] of Tool
      tools = page.map { |tool| JSON::Any.new(tool.to_definition) }
      result = {"tools" => JSON::Any.new(tools)} of String => JSON::Any
      next_offset = offset + page.size
      result["nextCursor"] = JSON::Any.new(next_offset.to_s) if next_offset < all.size
      result
    end

    # Resolves the tool, invokes it, and serialises the resulting ToolResult into
    # the MCP content envelope. When streaming, sends the final frame on the
    # session channel, closes it, and returns nil so the transport writes no
    # synchronous body.
    private def handle_tools_call(id : JSON::Any?, request : JSON::Any, session : Session?) : Hash(String, JSON::Any)?
      params = request["params"]?
      tool_name = params.try { |par| par["name"]?.try(&.as_s?) }
      return error_response(id, -32602, "missing tool name") unless tool_name

      args = params.try { |par| par["arguments"]?.try(&.as_h?) } || {} of String => JSON::Any
      progress = session.try(&.progress)

      result = invoke(tool_name, args, progress).to_result_hash

      if channel = session.try(&.channel)
        final = success_response(id, result)
        channel.send(JSON::Any.new(final)) rescue Channel::ClosedError
        channel.close rescue Channel::ClosedError
        return nil
      end

      success_response(id, result)
    end

    # Runs the tool handler, mapping failures to an isError ToolResult. ToolError's
    # message is surfaced to the client; any other exception yields a generic
    # message (internals are not leaked) and is logged.
    private def invoke(tool_name : String, args : Hash(String, JSON::Any), progress : Progress?) : ToolResult
      @server.dispatch(tool_name, args, progress)
    rescue ex : ToolError
      ToolResult.text(ex.message || "tool error", is_error: true)
    rescue ex
      Log.error { "tool #{tool_name} failed: #{ex.message}" }
      ToolResult.text("internal error", is_error: true)
    end

    private def success_response(id : JSON::Any?, result : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
      resp = {"jsonrpc" => JSON::Any.new("2.0"), "result" => JSON::Any.new(result)} of String => JSON::Any
      resp["id"] = id if id
      resp
    end

    private def error_response(id : JSON::Any?, code : Int32, message : String) : Hash(String, JSON::Any)
      err = {"code" => JSON::Any.new(code), "message" => JSON::Any.new(message)} of String => JSON::Any
      resp = {"jsonrpc" => JSON::Any.new("2.0"), "error" => JSON::Any.new(err)} of String => JSON::Any
      resp["id"] = id || JSON::Any.new(nil)
      resp
    end
  end
end
