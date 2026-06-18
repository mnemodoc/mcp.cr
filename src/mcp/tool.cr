module MCP
  # An MCP tool definition: its name, human description, the JSON Schema of its
  # arguments (stored pre-serialised), plus optional display title, output schema,
  # and behavioural annotations. Handlers live on MCP::Server, not here.
  class Tool
    getter name : String
    getter description : String
    getter schema_json : String
    getter title : String?
    getter output_schema_json : String?
    getter annotations : ToolAnnotations?

    def initialize(
      @name : String,
      @description : String,
      @schema_json : String,
      @title : String? = nil,
      @output_schema_json : String? = nil,
      @annotations : ToolAnnotations? = nil,
    )
    end

    # Builds (once) and caches the tools/list descriptor. inputSchema/outputSchema
    # are parsed from their stored JSON strings on first access only; title and
    # annotations are added when present so a minimal tool stays minimal.
    def to_definition : Hash(String, JSON::Any)
      @definition ||= build_definition
    end

    private def build_definition : Hash(String, JSON::Any)
      definition = {
        "name"        => JSON::Any.new(name),
        "description" => JSON::Any.new(description),
        "inputSchema" => JSON.parse(schema_json),
      } of String => JSON::Any
      title.try { |value| definition["title"] = JSON::Any.new(value) }
      output_schema_json.try { |value| definition["outputSchema"] = JSON.parse(value) }
      annotations.try { |value| definition["annotations"] = JSON::Any.new(value.to_json_object) }
      definition
    end

    @definition : Hash(String, JSON::Any)? = nil
  end
end
