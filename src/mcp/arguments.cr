module MCP
  # Opt-in ergonomic wrapper over a tool's raw argument hash. require_* raise
  # MCP::ToolError with a clear message; the *? variants return nil when absent
  # or of the wrong type. The handler still passes a plain Hash; tools choose to
  # wrap it.
  struct Arguments
    getter raw : Hash(String, JSON::Any)

    def initialize(@raw : Hash(String, JSON::Any))
    end

    # Returns the string at key, or raises MCP::ToolError when absent/not a string.
    def require_string(key : String) : String
      value = @raw[key]?.try(&.as_s?)
      raise ToolError.new("#{key} is required") unless value
      value
    end

    # The string at key, or nil when absent or not a string.
    def string?(key : String) : String?
      @raw[key]?.try(&.as_s?)
    end

    # The integer at key, or nil when absent or not an integer.
    def int?(key : String) : Int64?
      @raw[key]?.try(&.as_i64?)
    end

    # The boolean at key, or nil when absent or not a boolean.
    def bool?(key : String) : Bool?
      @raw[key]?.try(&.as_bool?)
    end

    # The string array at key, or nil when absent or not an array of strings.
    # A non-string element makes the whole value "not a string array" (nil),
    # honouring the ? contract — this accessor never raises.
    def string_array?(key : String) : Array(String)?
      array = @raw[key]?.try(&.as_a?)
      return nil unless array
      result = [] of String
      array.each do |element|
        string = element.as_s?
        return nil unless string
        result << string
      end
      result
    end
  end
end
