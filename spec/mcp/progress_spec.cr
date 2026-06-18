# spec/mcp/progress_spec.cr
require "../spec_helper"

Spectator.describe MCP::Progress do
  describe "#report" do
    it "sends a notifications/progress frame on the channel" do
      channel = Channel(JSON::Any).new(4)
      progress = MCP::Progress.new(channel, JSON::Any.new("tok"))
      progress.report(progress: 2, total: 5, message: "doc.md")
      frame = channel.receive
      expect(frame["method"].as_s).to eq("notifications/progress")
      params = frame["params"]
      expect(params["progressToken"].as_s).to eq("tok")
      expect(params["progress"].as_i).to eq(2)
      expect(params["total"].as_i).to eq(5)
      expect(params["message"].as_s).to eq("doc.md")
    end

    it "omits total and message when not given" do
      channel = Channel(JSON::Any).new(4)
      progress = MCP::Progress.new(channel, JSON::Any.new("tok"))
      progress.report(progress: 1)
      params = channel.receive["params"]
      expect(params.as_h.has_key?("total")).to be_false
      expect(params.as_h.has_key?("message")).to be_false
    end

    it "swallows a closed channel without raising" do
      channel = Channel(JSON::Any).new(1)
      channel.close
      progress = MCP::Progress.new(channel, JSON::Any.new("tok"))
      expect { progress.report(progress: 1) }.not_to raise_error
    end
  end
end
