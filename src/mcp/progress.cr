module MCP
  # Tool-facing progress reporter. A long-running tool calls #report to emit
  # MCP notifications/progress events while it runs. It is nil when the client
  # is not streaming, so tools guard with `progress.try &.report(...)`.
  class Progress
    def initialize(@channel : Channel(JSON::Any), @token : JSON::Any)
    end

    # Emits one notifications/progress frame on the channel. total and message
    # are optional per the MCP spec. A closed channel (disconnected client) is
    # swallowed so reporting never interrupts the running tool.
    def report(progress : Number, total : Number? = nil, message : String? = nil) : Nil
      params = {
        "progressToken" => @token,
        "progress"      => JSON::Any.new(progress.to_i64),
      } of String => JSON::Any
      params["total"] = JSON::Any.new(total.to_i64) if total
      params["message"] = JSON::Any.new(message) if message
      frame = JSON::Any.new({
        "jsonrpc" => JSON::Any.new("2.0"),
        "method"  => JSON::Any.new("notifications/progress"),
        "params"  => JSON::Any.new(params),
      } of String => JSON::Any)
      @channel.send(frame)
    rescue Channel::ClosedError
    end
  end
end
