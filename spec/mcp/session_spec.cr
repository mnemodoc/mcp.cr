# spec/mcp/session_spec.cr
require "../spec_helper"

Spectator.describe MCP::Session do
  it "is non-streaming with no channel" do
    session = MCP::Session.new
    expect(session.streaming?).to be_false
    expect(session.progress).to be_nil
  end

  it "exposes a progress reporter when a channel is present" do
    channel = Channel(JSON::Any).new(2)
    session = MCP::Session.new(channel: channel, progress_token: JSON::Any.new("tok"))
    expect(session.streaming?).to be_true
    # ameba:disable Lint/NotNil
    session.progress.not_nil!.report(progress: 1, total: 2)
    frame = channel.receive
    expect(frame["method"].as_s).to eq("notifications/progress")
    expect(frame["params"]["progressToken"].as_s).to eq("tok")
  end
end
