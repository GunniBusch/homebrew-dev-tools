# frozen_string_literal: true

require_relative "test_helper"

class BottlesTest < BrewDevToolsTestCase
  class CaptureShell < BrewDevTools::Shell
    def initialize(payload:)
      super()
      @payload = payload
      @commands = []
    end

    attr_reader :commands

    def run!(*command, **_kwargs)
      @commands << command
      BrewDevTools::Shell::Result.new(
        command: command,
        status: 0,
        stdout: JSON.dump(@payload),
        stderr: "",
      )
    end
  end

  def test_lists_bottle_archive_contents_for_tag
    stdout = StringIO.new
    shell = CaptureShell.new(payload: { "formulae" => [formula_payload("foo")] })
    archive_fetcher = lambda do |url|
      assert_equal "https://ghcr.io/v2/homebrew/core/foo/blobs/sha256:aaaaaaaa", url
      [
        "foo/1.2.3/.brew/foo.rb",
        "foo/1.2.3/bin/foo",
      ]
    end

    BrewDevTools::Bottles.new(
      shell: shell,
      stdout: stdout,
      archive_fetcher: archive_fetcher,
      options: { formulas: ["foo"], contents: true, tag: "arm64_sequoia" },
    ).run

    output = stdout.string
    assert_includes output, "foo 1.2.3"
    assert_includes output, "tag: arm64_sequoia"
    assert_includes output, "entries: 2"
    assert_includes output, "foo/1.2.3/bin/foo"
  end

  def test_lists_stable_bottle_metadata
    stdout = StringIO.new
    shell = CaptureShell.new(payload: { "formulae" => [formula_payload("foo")] })

    BrewDevTools::Bottles.new(
      shell: shell,
      stdout: stdout,
      options: { formulas: ["foo"] },
    ).run

    output = stdout.string
    assert_includes output, "foo 1.2.3"
    assert_includes output, "root_url: https://ghcr.io/v2/homebrew/core"
    assert_includes output, "tags:    arm64_sequoia, sonoma"
    assert_includes output, "arm64_sequoia: cellar=:any_skip_relocation sha256=aaaaaaaaaaaa"
    refute_includes output, "url=https://ghcr.io/v2/homebrew/core/foo"
    assert_equal ["brew", "info", "--json=v2", "foo"], shell.commands.first
  end

  def test_lists_full_urls_when_requested
    stdout = StringIO.new
    shell = CaptureShell.new(payload: { "formulae" => [formula_payload("foo")] })

    BrewDevTools::Bottles.new(
      shell: shell,
      stdout: stdout,
      options: { formulas: ["foo"], show_urls: true },
    ).run

    assert_includes stdout.string, "url=https://ghcr.io/v2/homebrew/core/foo/blobs/sha256:aaaaaaaa"
  end

  def test_compares_two_formula_bottles
    stdout = StringIO.new
    shell = CaptureShell.new(
      payload: {
        "formulae" => [
          formula_payload("foo"),
          formula_payload(
            "bar",
            rebuild: 1,
            root_url: "https://ghcr.io/v2/homebrew/core-alt",
            files: {
              "arm64_sequoia" => {
                "cellar" => ":any_skip_relocation",
                "url" => "https://ghcr.io/v2/homebrew/core-alt/bar/blobs/sha256:cccccccc",
                "sha256" => "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
              },
              "arm64_linux" => {
                "cellar" => ":any",
                "url" => "https://ghcr.io/v2/homebrew/core-alt/bar/blobs/sha256:dddddddd",
                "sha256" => "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
              },
            },
          ),
        ],
      },
    )

    BrewDevTools::Bottles.new(
      shell: shell,
      stdout: stdout,
      options: { formulas: %w[foo bar], compare: true },
    ).run

    output = stdout.string
    assert_includes output, "Compare: foo 1.2.3 <> bar 1.2.3"
    assert_includes output, "rebuild: 0 <> 1"
    assert_includes output, "only in foo: sonoma"
    assert_includes output, "only in bar: arm64_linux"
    assert_includes output, "arm64_sequoia: sha256 aaaaaaaaaaaa <> cccccccccccc; url differs"
  end

  def test_compares_bottle_archive_contents
    stdout = StringIO.new
    shell = CaptureShell.new(payload: { "formulae" => [formula_payload("foo"), formula_payload("bar")] })
    archive_fetcher = lambda do |url|
      case url
      when "https://ghcr.io/v2/homebrew/core/foo/blobs/sha256:aaaaaaaa"
        [
          "foo/1.2.3/.brew/foo.rb",
          "foo/1.2.3/bin/foo",
          "foo/1.2.3/share/man/man1/foo.1",
        ]
      when "https://ghcr.io/v2/homebrew/core/bar/blobs/sha256:aaaaaaaa"
        [
          "foo/1.2.3/.brew/foo.rb",
          "foo/1.2.3/bin/foo",
          "foo/1.2.3/lib/libbar.dylib",
        ]
      else
        flunk "unexpected bottle url #{url}"
      end
    end

    BrewDevTools::Bottles.new(
      shell: shell,
      stdout: stdout,
      archive_fetcher: archive_fetcher,
      options: { formulas: %w[foo bar], compare: true, contents: true, tag: "arm64_sequoia" },
    ).run

    output = stdout.string
    assert_includes output, "Compare contents: foo arm64_sequoia <> bar arm64_sequoia"
    assert_includes output, "common entries: 2"
    assert_includes output, "only in foo: foo/1.2.3/share/man/man1/foo.1"
    assert_includes output, "only in bar: foo/1.2.3/lib/libbar.dylib"
  end

  def test_compare_requires_exactly_two_formulae
    error = assert_raises(BrewDevTools::ValidationError) do
      BrewDevTools::Bottles.new(
        shell: CaptureShell.new(payload: { "formulae" => [] }),
        stdout: StringIO.new,
        options: { formulas: ["foo"], compare: true },
      ).run
    end

    assert_equal "--compare expects exactly two formula names.", error.message
  end

  def test_contents_requires_tag
    error = assert_raises(BrewDevTools::ValidationError) do
      BrewDevTools::Bottles.new(
        shell: CaptureShell.new(payload: { "formulae" => [] }),
        stdout: StringIO.new,
        options: { formulas: ["foo"], contents: true },
      ).run
    end

    assert_equal "--contents requires --tag so a specific bottle can be inspected.", error.message
  end

  private

  def formula_payload(name, rebuild: 0, revision: 0, root_url: "https://ghcr.io/v2/homebrew/core", files: nil)
    files ||= {
      "arm64_sequoia" => {
        "cellar" => ":any_skip_relocation",
        "url" => "https://ghcr.io/v2/homebrew/core/#{name}/blobs/sha256:aaaaaaaa",
        "sha256" => "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      },
      "sonoma" => {
        "cellar" => "/opt/homebrew/Cellar",
        "url" => "https://ghcr.io/v2/homebrew/core/#{name}/blobs/sha256:bbbbbbbb",
        "sha256" => "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      },
    }

    {
      "name" => name,
      "full_name" => name,
      "revision" => revision,
      "versions" => { "stable" => "1.2.3" },
      "bottle" => {
        "stable" => {
          "rebuild" => rebuild,
          "root_url" => root_url,
          "files" => files,
        },
      },
    }
  end
end
