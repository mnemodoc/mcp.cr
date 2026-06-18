module MCP
  # Raised by a tool handler to signal a business-level failure. The shared
  # handler maps it to an MCP response with isError set to true.
  class ToolError < Exception
  end
end
