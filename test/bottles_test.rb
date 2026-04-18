# frozen_string_literal: true

require_relative "test_helper"

class BottlesTest < BrewDevToolsTestCase
  class CaptureShell < BrewDevTools::Shell
    def initialize(payload:, cache_paths: {})
      super()
      @payload = payload
      @cache_paths = cache_paths
      @commands = []
    end

    attr_reader :commands

    def run!(*command, **_kwargs)
      @commands << command
      if command[1] == "--cache"
        formula = command.last
        tag = command.find { |arg| arg.start_with?("--bottle-tag=") }.split("=", 2).last
        return BrewDevTools::Shell::Result.new(
          command: command,
          status: 0,
          stdout: "#{@cache_paths.fetch([formula, tag], "/tmp/#{formula}-#{tag}.tar.gz")}\n",
          stderr: "",
        )
      end

      if command[1] == "fetch"
        return BrewDevTools::Shell::Result.new(
          command: command,
          status: 0,
          stdout: "",
          stderr: "",
        )
      end

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
    shell = CaptureShell.new(
      payload: { "formulae" => [formula_payload("foo")] },
      cache_paths: { ["foo", "arm64_sequoia"] => "/tmp/foo-arm64_sequoia.tar.gz" },
    )
    archive_fetcher = lambda do |path|
      assert_equal "/tmp/foo-arm64_sequoia.tar.gz", path
      [
        manifest_entry("foo/1.2.3/.brew/foo.rb", digest: "a" * 64, size: 120),
        manifest_entry("foo/1.2.3/bin/foo", digest: "b" * 64, size: 42),
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
    assert_includes shell.commands, ["brew", "--cache", "--bottle-tag=arm64_sequoia", "foo"]
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

  def test_compares_same_formula_tags_for_all_bottle_candidate
    stdout = StringIO.new
    shell = CaptureShell.new(
      payload: { "formulae" => [formula_payload("foo")] },
      cache_paths: {
        ["foo", "arm64_sequoia"] => "/tmp/foo-arm64_sequoia.tar.gz",
        ["foo", "sonoma"] => "/tmp/foo-sonoma.tar.gz",
      },
    )
    archive_fetcher = lambda do |path|
      case path
      when "/tmp/foo-arm64_sequoia.tar.gz", "/tmp/foo-sonoma.tar.gz"
        [
          manifest_entry("foo/1.2.3/.brew/foo.rb", digest: "a" * 64, size: 120),
          manifest_entry("foo/1.2.3/bin/foo", digest: "b" * 64, size: 42),
        ]
      else
        flunk "unexpected bottle cache path #{path}"
      end
    end
    diffoscope_runner = lambda do |_left_path, _right_path, formula_name, left_tag, right_tag|
      assert_equal "foo", formula_name
      assert_equal "arm64_sequoia", left_tag
      assert_equal "sonoma", right_tag

      {
        summary: "no differences",
        path: "/tmp/foo-diffoscope.txt",
        excerpt: "",
      }
    end

    BrewDevTools::Bottles.new(
      shell: shell,
      stdout: stdout,
      archive_fetcher: archive_fetcher,
      diffoscope_runner: diffoscope_runner,
      options: {
        formulas: ["foo"],
        compare: true,
        contents: true,
        tag: "arm64_sequoia",
        against_tag: "sonoma",
      },
    ).run

    output = stdout.string
    assert_includes output, "Compare contents: foo arm64_sequoia <> foo sonoma"
    assert_includes output, "archive entries match: true"
    assert_includes output, "all bottle candidate: yes"
    assert_includes output, "only in arm64_sequoia: (none)"
    assert_includes output, "only in sonoma: (none)"
    assert_includes output, "changed entries: (none)"
    assert_includes output, "diffoscope: no differences"
    assert_includes output, "diffoscope report: /tmp/foo-diffoscope.txt"
  end

  def test_compares_same_formula_tags_and_shows_changed_entries
    stdout = StringIO.new
    shell = CaptureShell.new(
      payload: { "formulae" => [formula_payload("foo")] },
      cache_paths: {
        ["foo", "arm64_sequoia"] => "/tmp/foo-arm64_sequoia.tar.gz",
        ["foo", "sonoma"] => "/tmp/foo-sonoma.tar.gz",
      },
    )
    archive_fetcher = lambda do |path|
      case path
      when "/tmp/foo-arm64_sequoia.tar.gz"
        [
          manifest_entry("foo/1.2.3/.brew/foo.rb", digest: "a" * 64, size: 120),
          manifest_entry("foo/1.2.3/bin/foo", digest: "b" * 64, size: 42),
        ]
      when "/tmp/foo-sonoma.tar.gz"
        [
          manifest_entry("foo/1.2.3/.brew/foo.rb", digest: "a" * 64, size: 120),
          manifest_entry("foo/1.2.3/bin/foo", digest: "c" * 64, size: 42),
        ]
      else
        flunk "unexpected bottle cache path #{path}"
      end
    end
    diffoscope_runner = lambda do |_left_path, _right_path, _formula_name, _left_tag, _right_tag|
      {
        summary: "differences detected",
        path: "/tmp/foo-diffoscope.txt",
        excerpt: "--- /tmp/foo-arm64_sequoia.tar.gz\n+++ /tmp/foo-sonoma.tar.gz\n@@ binary @@\n",
      }
    end

    BrewDevTools::Bottles.new(
      shell: shell,
      stdout: stdout,
      archive_fetcher: archive_fetcher,
      diffoscope_runner: diffoscope_runner,
      options: {
        formulas: ["foo"],
        compare: true,
        contents: true,
        tag: "arm64_sequoia",
        against_tag: "sonoma",
      },
    ).run

    output = stdout.string
    assert_includes output, "all bottle candidate: no"
    assert_includes output, "changed entries:"
    assert_includes output, "foo/1.2.3/bin/foo: digest bbbbbbbbbbbb <> cccccccccccc"
    assert_includes output, "diffoscope: differences detected"
    assert_includes output, "diffoscope excerpt:"
    assert_includes output, "--- /tmp/foo-arm64_sequoia.tar.gz"
  end

  def test_compare_same_formula_metadata_for_two_tags
    stdout = StringIO.new
    shell = CaptureShell.new(payload: { "formulae" => [formula_payload("foo")] })

    BrewDevTools::Bottles.new(
      shell: shell,
      stdout: stdout,
      options: {
        formulas: ["foo"],
        compare: true,
        tag: "arm64_sequoia",
        against_tag: "sonoma",
      },
    ).run

    output = stdout.string
    assert_includes output, "Compare tags: foo 1.2.3"
    assert_includes output, "arm64_sequoia <> sonoma"
    assert_includes output, "urls differ: true"
  end

  def test_compares_two_formula_bottle_archive_contents
    stdout = StringIO.new
    shell = CaptureShell.new(
      payload: { "formulae" => [formula_payload("foo"), formula_payload("bar")] },
      cache_paths: {
        ["foo", "arm64_sequoia"] => "/tmp/foo-arm64_sequoia.tar.gz",
        ["bar", "arm64_sequoia"] => "/tmp/bar-arm64_sequoia.tar.gz",
      },
    )
    archive_fetcher = lambda do |path|
      case path
      when "/tmp/foo-arm64_sequoia.tar.gz"
        [
          manifest_entry("foo/1.2.3/.brew/foo.rb", digest: "a" * 64, size: 120),
          manifest_entry("foo/1.2.3/bin/foo", digest: "b" * 64, size: 42),
          manifest_entry("foo/1.2.3/share/man/man1/foo.1", digest: "d" * 64, size: 12),
        ]
      when "/tmp/bar-arm64_sequoia.tar.gz"
        [
          manifest_entry("foo/1.2.3/.brew/foo.rb", digest: "a" * 64, size: 120),
          manifest_entry("foo/1.2.3/bin/foo", digest: "b" * 64, size: 42),
          manifest_entry("foo/1.2.3/lib/libbar.dylib", digest: "e" * 64, size: 16),
        ]
      else
        flunk "unexpected bottle cache path #{path}"
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

  def test_compare_requires_two_formulae_or_two_tags
    error = assert_raises(BrewDevTools::ValidationError) do
      BrewDevTools::Bottles.new(
        shell: CaptureShell.new(payload: { "formulae" => [] }),
        stdout: StringIO.new,
        options: { formulas: ["foo"], compare: true },
      ).run
    end

    assert_equal "--compare expects either two formula names or one formula with --tag and --against-tag.", error.message
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

  def manifest_entry(name, digest: nil, size: 0, type: "0", linkname: "")
    BrewDevTools::Bottles::ManifestEntry.new(
      name: name,
      type: type,
      digest: digest,
      size: size,
      linkname: linkname,
    )
  end

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
