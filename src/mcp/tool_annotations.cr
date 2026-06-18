module MCP
  # Behavioural hints for a tool, surfaced in tools/list. All fields are optional
  # and only set fields are serialised. Field names match the MCP ToolAnnotations
  # schema (2025-06-18). A nil hint means "unspecified" (the client applies the
  # spec default); an explicit false is emitted as false.
  struct ToolAnnotations
    def initialize(@title : String? = nil, @read_only_hint : Bool? = nil, @destructive_hint : Bool? = nil, @idempotent_hint : Bool? = nil, @open_world_hint : Bool? = nil)
    end

    def to_json_object : Hash(String, JSON::Any)
      obj = {} of String => JSON::Any
      @title.try { |value| obj["title"] = JSON::Any.new(value) }
      @read_only_hint.try { |value| obj["readOnlyHint"] = JSON::Any.new(value) }
      @destructive_hint.try { |value| obj["destructiveHint"] = JSON::Any.new(value) }
      @idempotent_hint.try { |value| obj["idempotentHint"] = JSON::Any.new(value) }
      @open_world_hint.try { |value| obj["openWorldHint"] = JSON::Any.new(value) }
      obj
    end
  end
end
