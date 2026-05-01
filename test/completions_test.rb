# frozen_string_literal: true

require_relative "test_helper"

class CompletionsTest < BrewDevToolsTestCase
  ROOT = Pathname(__dir__).parent

  def test_completion_files_are_in_homebrew_linked_paths
    assert_path_exists ROOT/"completions/bash/brew-dev-tools"
    assert_path_exists ROOT/"completions/zsh/_brew_prsync"
    assert_path_exists ROOT/"completions/zsh/_brew_wwdd"
    assert_path_exists ROOT/"completions/zsh/_brew_bottles"
    assert_path_exists ROOT/"completions/fish/brew-dev-tools.fish"
  end

  def test_bash_completion_dispatches_brew_subcommands
    completion = File.read(ROOT/"completions/bash/brew-dev-tools")

    assert_includes completion, "prsync)"
    assert_includes completion, "wwdd)"
    assert_includes completion, "bottles)"
    assert_includes completion, "complete -o bashdefault -o default -F _brew_dev_tools_brew brew"
  end

  def test_completion_options_match_command_interfaces
    expected_options = {
      "prsync" => %w[--apply --push --pr --ai --closes --fixes --ref --message --style --base],
      "wwdd" => %w[--online --install --base],
      "bottles" => %w[--compare --contents --tag --against-tag --urls],
    }

    expected_options.each do |command, options|
      command_source = File.read(ROOT/"cmd/#{command}.rb")
      completion_sources = completion_sources_for(command)

      options.each do |option|
        assert_includes command_source, option
        assert_includes completion_sources, option
      end
    end
  end

  def test_zsh_completion_names_match_homebrew_dispatch_names
    %w[prsync wwdd bottles].each do |command|
      assert_match(/_brew_#{command}\(\)/, File.read(ROOT/"completions/zsh/_brew_#{command}"))
    end
  end

  private

  def completion_sources_for(command)
    [
      File.read(ROOT/"completions/bash/brew-dev-tools"),
      File.read(ROOT/"completions/zsh/_brew_#{command}"),
      File.read(ROOT/"completions/fish/brew-dev-tools.fish"),
    ].join("\n")
  end
end
