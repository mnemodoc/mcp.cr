module MCP
  # Registry of MCP tools plus the dispatch entry point used by the handler.
  # Tools are registered at startup (not thread-safe); dispatch is read-only and
  # safe to call concurrently from request fibers.
  class Server
    getter name : String
    getter version : String

    # A tool handler receives the parsed arguments and an optional progress
    # reporter (nil when the client is not streaming), and returns either the
    # result text (auto-wrapped as one text block) or a full MCP::ToolResult.
    # It raises MCP::ToolError on a business failure.
    alias Handler = Proc(Hash(String, JSON::Any), MCP::Progress?, String | ToolResult)

    def initialize(@name : String, @version : String)
      @tools = {} of String => Tool
      @handlers = {} of String => Handler
    end

    # Registers a tool. schema (and output_schema, when given) are serialised to
    # JSON internally, so callers can pass a NamedTuple literal, a Hash, or a
    # JSON::Any. title and annotations are optional display/behaviour metadata.
    def tool(name : String, description : String, schema : T,
             title : String? = nil, output_schema = nil, annotations : ToolAnnotations? = nil,
             &handler : Hash(String, JSON::Any), MCP::Progress? -> (String | ToolResult)) : Nil forall T
      output_schema_json = output_schema.nil? ? nil : output_schema.to_json
      @tools[name] = Tool.new(
        name: name, description: description, schema_json: schema.to_json,
        title: title, output_schema_json: output_schema_json, annotations: annotations,
      )
      @handlers[name] = handler
    end

    # The registered tool descriptors, for the tools/list response.
    def tool_definitions : Array(Tool)
      @tools.values
    end

    # Capabilities derived from what is registered, not hardcoded. Adding future
    # feature registries (resources, prompts) makes their block appear here on
    # its own without touching the handshake code.
    def capabilities : Hash(String, JSON::Any)
      caps = {} of String => JSON::Any
      caps["tools"] = JSON::Any.new({} of String => JSON::Any) unless @tools.empty?
      caps
    end

    # Invokes a tool's handler and normalises its result. Raises MCP::ToolError
    # when the tool is unknown. A String handler result is wrapped into a single
    # text-block ToolResult; a ToolResult is returned as-is.
    def dispatch(tool_name : String, args : Hash(String, JSON::Any),
                 progress : MCP::Progress? = nil) : ToolResult
      handler = @handlers[tool_name]?
      raise ToolError.new("unknown tool: #{tool_name}") unless handler
      result = handler.call(args, progress)
      result.is_a?(ToolResult) ? result : ToolResult.text(result)
    end
  end
end
