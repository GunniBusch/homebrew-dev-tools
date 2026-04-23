# frozen_string_literal: true

require_relative "test_helper"

class AIContextTest < BrewDevToolsTestCase
  def test_detects_from_environment
    result = BrewDevTools::AIContext.new(env: { "CODEX_SHELL" => "1" }).detect

    assert_equal true, result.fetch("detected")
    assert_equal "Codex", result.fetch("tool")
    assert_equal "env", result.fetch("source")
  end

  def test_detects_from_process_ancestry_when_environment_is_missing
    ancestry_loader = ->(_pid) { ["/opt/homebrew/Library/Homebrew/vendor/portable-ruby/bin/ruby", "/Applications/Codex.app/Contents/MacOS/Codex"] }

    result = BrewDevTools::AIContext.new(
      env: {},
      process_ancestry_loader: ancestry_loader,
    ).detect

    assert_equal true, result.fetch("detected")
    assert_equal "Codex", result.fetch("tool")
    assert_equal "process", result.fetch("source")
  end

  def test_returns_undetected_when_no_signal_is_present
    result = BrewDevTools::AIContext.new(env: {}, process_ancestry_loader: ->(_pid) { [] }).detect

    assert_equal false, result.fetch("detected")
    assert_nil result.fetch("tool")
    assert_nil result.fetch("source")
  end
end
