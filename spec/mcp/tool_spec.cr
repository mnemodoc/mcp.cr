# spec/mcp/tool_spec.cr
require "../spec_helper"

Spectator.describe MCP::Tool do
  describe "#to_definition" do
    it "exposes name, description and parsed inputSchema" do
      schema = {type: "object", properties: {q: {type: "string"}}}.to_json
      tool = MCP::Tool.new(name: "search", description: "Find stuff", schema_json: schema)
      definition = tool.to_definition
      expect(definition["name"].as_s).to eq("search")
      expect(definition["description"].as_s).to eq("Find stuff")
      expect(definition["inputSchema"]["type"].as_s).to eq("object")
    end

    it "omits title, outputSchema and annotations when absent" do
      tool = MCP::Tool.new(name: "t", description: "d", schema_json: %({"type":"object"}))
      definition = tool.to_definition
      expect(definition.has_key?("title")).to be_false
      expect(definition.has_key?("outputSchema")).to be_false
      expect(definition.has_key?("annotations")).to be_false
    end

    it "returns the same object on repeated calls (memoised)" do
      tool = MCP::Tool.new(name: "t", description: "d", schema_json: %({"type":"object"}))
      expect(tool.to_definition).to be(tool.to_definition)
    end

    it "memoises across Server#tool_definitions accesses (reference semantics)" do
      server = MCP::Server.new(name: "s", version: "1.0.0")
      server.tool("t", description: "d", schema: {type: "object"}) { |_a, _p| "x" }
      first = server.tool_definitions.first
      second = server.tool_definitions.first
      expect(first.to_definition).to be(second.to_definition)
    end

    it "includes title, parsed outputSchema and annotations when present" do
      tool = MCP::Tool.new(
        name: "t", description: "d", schema_json: %({"type":"object"}),
        title: "Title",
        output_schema_json: %({"type":"object","properties":{"x":{"type":"number"}}}),
        annotations: MCP::ToolAnnotations.new(read_only_hint: true),
      )
      definition = tool.to_definition
      expect(definition["title"].as_s).to eq("Title")
      expect(definition["outputSchema"]["properties"]["x"]["type"].as_s).to eq("number")
      expect(definition["annotations"]["readOnlyHint"].as_bool).to be_true
    end
  end
end
