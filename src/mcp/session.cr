module MCP
  # Per-connection context threaded into the handler. Carries the optional
  # server→client event channel (present only while streaming), the client's
  # progressToken, and the originating request id. This is the seam reserved for
  # Family 2 server-initiated notifications: a future #notify will live here
  # without changing Handler#handle.
  class Session
    getter channel : Channel(JSON::Any)?
    getter progress_token : JSON::Any
    # Reserved for Family 2: a future #notify correlates server-initiated frames
    # to the originating request. Carried by the streaming transport but unread
    # in 1.0 (the handler addresses the final frame via the request id directly).
    getter request_id : JSON::Any

    def initialize(@channel : Channel(JSON::Any)? = nil,
                   @progress_token : JSON::Any = JSON::Any.new(nil),
                   @request_id : JSON::Any = JSON::Any.new(nil))
    end

    # True when a server→client event channel is attached (streaming transport).
    def streaming? : Bool
      !@channel.nil?
    end

    # A progress reporter bound to the channel, or nil when not streaming, so
    # tools guard with `progress.try &.report(...)`.
    def progress : Progress?
      @channel.try { |chan| Progress.new(chan, @progress_token) }
    end
  end
end
