# spec/mcp/arguments_spec.cr
require "../spec_helper"

Spectator.describe MCP::Arguments do
  def args(json : String) : MCP::Arguments
    MCP::Arguments.new(JSON.parse(json).as_h)
  end

  describe "#require_string" do
    it "returns the string value" do
      expect(args(%({"q":"hi"})).require_string("q")).to eq("hi")
    end

    it "raises MCP::ToolError when missing" do
      expect { args("{}").require_string("q") }.to raise_error(MCP::ToolError, /q is required/)
    end

    it "raises MCP::ToolError when not a string" do
      expect { args(%({"q":5})).require_string("q") }.to raise_error(MCP::ToolError)
    end
  end

  describe "optional accessors" do
    it "string? returns nil when absent" do
      expect(args("{}").string?("m")).to be_nil
    end

    it "int? parses an integer" do
      expect(args(%({"k":3})).int?("k")).to eq(3_i64)
    end

    it "bool? parses a boolean" do
      expect(args(%({"b":true})).bool?("b")).to be_true
    end

    it "string_array? maps a JSON array of strings" do
      expect(args(%({"f":["a","b"]})).string_array?("f")).to eq(["a", "b"])
    end

    it "string_array? returns nil when absent" do
      expect(args("{}").string_array?("f")).to be_nil
    end

    it "string_array? returns nil (never raises) on a non-string element" do
      expect(args(%({"f":["a",5]})).string_array?("f")).to be_nil
    end
  end
end
