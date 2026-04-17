# frozen_string_literal: true

require_relative "test_helper"

class ShellTest < BrewDevToolsTestCase
  def test_run_without_chdir
    result = BrewDevTools::Shell.new.run!(
      "ruby",
      "-e",
      "print Dir.pwd",
    )

    assert result.success?
    assert_equal Dir.pwd, result.stdout
  end

  def test_run_with_chdir
    with_tmpdir do |dir|
      result = BrewDevTools::Shell.new.run!(
        "ruby",
        "-e",
        "print Dir.pwd",
        chdir: dir.to_s,
      )

      assert result.success?
      assert_equal File.realpath(dir.to_s), result.stdout
    end
  end
end
