# spec/mcp/content_spec.cr
require "../spec_helper"

Spectator.describe MCP::Content do
  describe "TextContent" do
    it "serialises to a text block" do
      obj = MCP::TextContent.new("hello").to_json_object
      expect(obj["type"].as_s).to eq("text")
      expect(obj["text"].as_s).to eq("hello")
      expect(obj.has_key?("annotations")).to be_false
    end

    it "includes annotations when present" do
      ann = MCP::ContentAnnotations.new(audience: ["user"], priority: 0.9)
      obj = MCP::TextContent.new("hi", annotations: ann).to_json_object
      expect(obj["annotations"]["audience"].as_a.map(&.as_s)).to eq(["user"])
      expect(obj["annotations"]["priority"].as_f).to eq(0.9)
    end
  end

  describe "ImageContent" do
    it "serialises data and mimeType" do
      obj = MCP::ImageContent.new(data: "b64", mime_type: "image/png").to_json_object
      expect(obj["type"].as_s).to eq("image")
      expect(obj["data"].as_s).to eq("b64")
      expect(obj["mimeType"].as_s).to eq("image/png")
    end
  end

  describe "AudioContent" do
    it "serialises with type audio" do
      obj = MCP::AudioContent.new(data: "b64", mime_type: "audio/wav").to_json_object
      expect(obj["type"].as_s).to eq("audio")
      expect(obj["mimeType"].as_s).to eq("audio/wav")
    end
  end

  describe "ResourceLink" do
    it "serialises uri and name, omitting absent optionals" do
      obj = MCP::ResourceLink.new(uri: "file:///x.rs", name: "x.rs").to_json_object
      expect(obj["type"].as_s).to eq("resource_link")
      expect(obj["uri"].as_s).to eq("file:///x.rs")
      expect(obj["name"].as_s).to eq("x.rs")
      expect(obj.has_key?("description")).to be_false
      expect(obj.has_key?("mimeType")).to be_false
    end
  end

  describe "EmbeddedResource" do
    it "nests the resource object with text" do
      obj = MCP::EmbeddedResource.new(uri: "file:///x.rs", text: "fn main(){}", mime_type: "text/x-rust").to_json_object
      expect(obj["type"].as_s).to eq("resource")
      expect(obj["resource"]["uri"].as_s).to eq("file:///x.rs")
      expect(obj["resource"]["text"].as_s).to eq("fn main(){}")
      expect(obj["resource"]["mimeType"].as_s).to eq("text/x-rust")
    end
  end
end
