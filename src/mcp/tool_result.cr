module MCP
  # The result of a tool invocation: one or more content blocks, optional
  # machine-readable structured content, and an error flag. A bare String returned
  # by a handler is wrapped via .text into a single text block by MCP::Server.
  struct ToolResult
    getter content : Array(Content)
    getter structured_content : JSON::Any?
    getter? is_error : Bool

    def initialize(@content : Array(Content) = [] of Content, @structured_content : JSON::Any? = nil, @is_error : Bool = false)
    end

    # A result that is a single text block.
    def self.text(text : String, is_error : Bool = false) : ToolResult
      new(content: [TextContent.new(text).as(Content)], is_error: is_error)
    end

    # Builds the tools/call result object. When structured_content is present but
    # no content block was supplied, a text block carrying the serialised JSON is
    # added (spec-recommended fallback for clients that ignore structuredContent).
    def to_result_hash : Hash(String, JSON::Any)
      blocks = @content
      if (structured = @structured_content) && blocks.empty?
        blocks = [TextContent.new(structured.to_json).as(Content)]
      end
      result = {
        "content" => JSON::Any.new(blocks.map { |block| JSON::Any.new(block.to_json_object) }),
        "isError" => JSON::Any.new(@is_error),
      } of String => JSON::Any
      @structured_content.try { |structured_val| result["structuredContent"] = structured_val }
      result
    end
  end
end
