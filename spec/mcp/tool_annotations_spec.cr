require "../spec_helper"

Spectator.describe MCP::ToolAnnotations do
  it "emits only the set fields under their MCP names" do
    obj = MCP::ToolAnnotations.new(read_only_hint: true, title: "Reader").to_json_object
    expect(obj["readOnlyHint"].as_bool).to be_true
    expect(obj["title"].as_s).to eq("Reader")
    expect(obj.has_key?("destructiveHint")).to be_false
    expect(obj.has_key?("idempotentHint")).to be_false
    expect(obj.has_key?("openWorldHint")).to be_false
  end

  it "emits a false hint when explicitly set to false" do
    obj = MCP::ToolAnnotations.new(destructive_hint: false).to_json_object
    expect(obj["destructiveHint"].as_bool).to be_false
  end

  it "is empty when nothing is set" do
    expect(MCP::ToolAnnotations.new.to_json_object.empty?).to be_true
  end
end
