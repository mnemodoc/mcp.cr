module MCP
  # Optional metadata for a content block, shared with resources and prompts:
  # who it is for, how important it is, and when it last changed. Only set fields
  # are serialised.
  struct ContentAnnotations
    def initialize(@audience : Array(String)? = nil, @priority : Float64? = nil, @last_modified : String? = nil)
    end

    # Builds the annotations object, omitting absent fields. Returns nil when
    # nothing is set so callers can skip the key entirely.
    def to_json_object : Hash(String, JSON::Any)?
      obj = {} of String => JSON::Any
      @audience.try { |roles| obj["audience"] = JSON::Any.new(roles.map { |role| JSON::Any.new(role) }) }
      @priority.try { |value| obj["priority"] = JSON::Any.new(value) }
      @last_modified.try { |value| obj["lastModified"] = JSON::Any.new(value) }
      obj.empty? ? nil : obj
    end
  end

  # A single content block of a tool result. Concrete subtypes map to the MCP
  # content shapes; each can carry optional annotations.
  abstract struct Content
    getter annotations : ContentAnnotations?

    # Serialises this block to its MCP JSON object.
    abstract def to_json_object : Hash(String, JSON::Any)

    # Merges the annotations key into an already-built object when present.
    protected def with_annotations(obj : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
      @annotations.try(&.to_json_object).try { |ann| obj["annotations"] = JSON::Any.new(ann) }
      obj
    end
  end

  # A plain-text content block.
  struct TextContent < Content
    def initialize(@text : String, @annotations : ContentAnnotations? = nil)
    end

    def to_json_object : Hash(String, JSON::Any)
      with_annotations({
        "type" => JSON::Any.new("text"),
        "text" => JSON::Any.new(@text),
      } of String => JSON::Any)
    end
  end

  # A base64-encoded image block.
  struct ImageContent < Content
    def initialize(@data : String, @mime_type : String, @annotations : ContentAnnotations? = nil)
    end

    def to_json_object : Hash(String, JSON::Any)
      with_annotations({
        "type"     => JSON::Any.new("image"),
        "data"     => JSON::Any.new(@data),
        "mimeType" => JSON::Any.new(@mime_type),
      } of String => JSON::Any)
    end
  end

  # A base64-encoded audio block.
  struct AudioContent < Content
    def initialize(@data : String, @mime_type : String, @annotations : ContentAnnotations? = nil)
    end

    def to_json_object : Hash(String, JSON::Any)
      with_annotations({
        "type"     => JSON::Any.new("audio"),
        "data"     => JSON::Any.new(@data),
        "mimeType" => JSON::Any.new(@mime_type),
      } of String => JSON::Any)
    end
  end

  # A link to a resource the client may fetch or subscribe to.
  struct ResourceLink < Content
    def initialize(@uri : String, @name : String, @description : String? = nil, @mime_type : String? = nil, @annotations : ContentAnnotations? = nil)
    end

    def to_json_object : Hash(String, JSON::Any)
      obj = {
        "type" => JSON::Any.new("resource_link"),
        "uri"  => JSON::Any.new(@uri),
        "name" => JSON::Any.new(@name),
      } of String => JSON::Any
      @description.try { |value| obj["description"] = JSON::Any.new(value) }
      @mime_type.try { |value| obj["mimeType"] = JSON::Any.new(value) }
      with_annotations(obj)
    end
  end

  # A resource embedded directly in the result (text or base64 blob).
  struct EmbeddedResource < Content
    def initialize(@uri : String, @text : String? = nil, @blob : String? = nil, @mime_type : String? = nil, @annotations : ContentAnnotations? = nil)
    end

    def to_json_object : Hash(String, JSON::Any)
      resource = {"uri" => JSON::Any.new(@uri)} of String => JSON::Any
      @mime_type.try { |value| resource["mimeType"] = JSON::Any.new(value) }
      @text.try { |value| resource["text"] = JSON::Any.new(value) }
      @blob.try { |value| resource["blob"] = JSON::Any.new(value) }
      with_annotations({
        "type"     => JSON::Any.new("resource"),
        "resource" => JSON::Any.new(resource),
      } of String => JSON::Any)
    end
  end
end
