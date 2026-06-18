# spec/mcp/server_spec.cr
require "../spec_helper"

Spectator.describe MCP::Server do
  let(server) { MCP::Server.new(name: "test-server", version: "9.9.9") }

  describe "#tool and #dispatch" do
    it "registers a tool and dispatches to its handler, wrapping a String result" do
      server.tool("echo", description: "Echoes", schema: {type: "object"}) do |args, _progress|
        args["msg"]?.try(&.as_s) || "empty"
      end
      result = server.dispatch("echo", {"msg" => JSON::Any.new("hi")})
      expect(result).to be_a(MCP::ToolResult)
      expect(result.content.first.to_json_object["text"].as_s).to eq("hi")
      expect(result.is_error?).to be_false
    end

    it "passes through a ToolResult returned by the handler" do
      server.tool("rich", description: "Rich", schema: {type: "object"}) do |_args, _progress|
        MCP::ToolResult.new(structured_content: JSON.parse(%({"k":1})))
      end
      result = server.dispatch("rich", {} of String => JSON::Any)
      # ameba:disable Lint/NotNil
      expect(result.structured_content.not_nil!["k"].as_i).to eq(1)
    end

    it "registers optional title, outputSchema and annotations" do
      server.tool("meta", description: "Meta", schema: {type: "object"},
        title: "Meta Tool",
        output_schema: {type: "object", properties: {n: {type: "number"}}},
        annotations: MCP::ToolAnnotations.new(read_only_hint: true)) { |_a, _p| "x" }
      definition = server.tool_definitions.find! { |tool| tool.name == "meta" }.to_definition
      expect(definition["title"].as_s).to eq("Meta Tool")
      expect(definition["outputSchema"]["properties"]["n"]["type"].as_s).to eq("number")
      expect(definition["annotations"]["readOnlyHint"].as_bool).to be_true
    end

    it "passes the progress reporter to the handler" do
      server.tool("work", description: "Works", schema: {type: "object"}) do |_args, progress|
        progress.try &.report(progress: 1, total: 1)
        "done"
      end
      channel = Channel(JSON::Any).new(2)
      progress = MCP::Progress.new(channel, JSON::Any.new("tok"))
      server.dispatch("work", {} of String => JSON::Any, progress)
      expect(channel.receive["method"].as_s).to eq("notifications/progress")
    end

    it "raises ToolError for an unregistered tool" do
      expect { server.dispatch("nope", {} of String => JSON::Any) }.to raise_error(MCP::ToolError)
    end
  end

  describe "#tool_definitions" do
    it "returns the registered tool descriptors" do
      server.tool("a", description: "A", schema: {type: "object"}) { |_a, _p| "x" }
      names = server.tool_definitions.map(&.name)
      expect(names).to contain("a")
    end
  end

  describe "#capabilities" do
    it "is empty with no tools" do
      expect(server.capabilities.empty?).to be_true
    end

    it "advertises tools once one is registered" do
      server.tool("a", description: "A", schema: {type: "object"}) { |_a, _p| "x" }
      expect(server.capabilities.has_key?("tools")).to be_true
    end
  end
end
