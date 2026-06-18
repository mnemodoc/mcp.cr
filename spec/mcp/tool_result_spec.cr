# spec/mcp/tool_result_spec.cr
require "../spec_helper"

Spectator.describe MCP::ToolResult do
  describe ".text" do
    it "wraps a string as a single text block with isError false" do
      hash = MCP::ToolResult.text("hi").to_result_hash
      expect(hash["content"].as_a.size).to eq(1)
      expect(hash["content"].as_a.first["type"].as_s).to eq("text")
      expect(hash["content"].as_a.first["text"].as_s).to eq("hi")
      expect(hash["isError"].as_bool).to be_false
      expect(hash.has_key?("structuredContent")).to be_false
    end

    it "carries the error flag" do
      hash = MCP::ToolResult.text("boom", is_error: true).to_result_hash
      expect(hash["isError"].as_bool).to be_true
    end
  end

  describe "#to_result_hash with structured content" do
    it "emits structuredContent and an auto text fallback when no block given" do
      structured = JSON.parse(%({"temperature":22.5}))
      hash = MCP::ToolResult.new(structured_content: structured).to_result_hash
      expect(hash["structuredContent"]["temperature"].as_f).to eq(22.5)
      expect(hash["content"].as_a.size).to eq(1)
      expect(JSON.parse(hash["content"].as_a.first["text"].as_s)["temperature"].as_f).to eq(22.5)
    end

    it "keeps explicit content blocks alongside structuredContent" do
      structured = JSON.parse(%({"k":1}))
      result = MCP::ToolResult.new(content: [MCP::TextContent.new("summary").as(MCP::Content)], structured_content: structured)
      hash = result.to_result_hash
      expect(hash["content"].as_a.size).to eq(1)
      expect(hash["content"].as_a.first["text"].as_s).to eq("summary")
      expect(hash["structuredContent"]["k"].as_i).to eq(1)
    end
  end

  describe "#to_result_hash with multiple blocks" do
    it "serialises every block in order" do
      result = MCP::ToolResult.new(content: [
        MCP::TextContent.new("a").as(MCP::Content),
        MCP::ImageContent.new(data: "b64", mime_type: "image/png").as(MCP::Content),
      ])
      blocks = result.to_result_hash["content"].as_a
      expect(blocks.map(&.["type"].as_s)).to eq(["text", "image"])
    end
  end
end
