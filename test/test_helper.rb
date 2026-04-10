# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "pathname"
require "stringio"
require "tmpdir"

require_relative "../lib/brew_dev_tools"

class BrewDevToolsTestCase < Minitest::Test
  private

  def with_tmpdir
    Dir.mktmpdir("brew-dev-tools-test-") do |dir|
      yield Pathname(dir)
    end
  end

  def init_repo(dir)
    run_cmd(dir, "git", "init", "-b", "master")
    run_cmd(dir, "git", "config", "user.name", "Test User")
    run_cmd(dir, "git", "config", "user.email", "test@example.com")
    run_cmd(dir, "git", "config", "commit.gpgsign", "false")
    run_cmd(dir, "git", "config", "tag.gpgSign", "false")
    run_cmd(dir, "git", "config", "push.gpgSign", "false")
    FileUtils.mkdir_p(dir/"Formula")
  end

  def formula_file_path(name, subdir: nil)
    return "Formula/#{name}.rb" if subdir.nil? || subdir.empty?

    "Formula/#{subdir}/#{name}.rb"
  end

  def init_bare_remote(dir)
    remote = dir.parent/"#{dir.basename}-remote.git"
    run_cmd(dir.parent, "git", "init", "--bare", remote.to_s)
    remote
  end

  def attach_origin(dir, remote)
    run_cmd(dir, "git", "remote", "add", "origin", remote.to_s)
  end

  def commit_formula(dir, name, content, message, subdir: nil)
    path = formula_file_path(name, subdir: subdir)
    FileUtils.mkdir_p(dir/File.dirname(path))
    File.write(dir/path, content)
    run_cmd(dir, "git", "add", "--", path)
    run_cmd(dir, "git", "commit", "-m", message)
  end

  def formula_content(name, version, body: "")
    <<~RUBY
      class #{camelize(name)} < Formula
        desc "Test formula"
        homepage "https://example.com/#{name}"
        url "https://example.com/#{name}-#{version}.tar.gz"
        sha256 "#{'a' * 64}"
        #{body}
      end
    RUBY
  end

  def run_cmd(dir, *command, env: {})
    stdout, stderr, status = Open3.capture3(env, *command, chdir: dir.to_s)
    raise "#{command.join(' ')} failed: #{stderr}" unless status.success?

    stdout
  end

  def camelize(name)
    name.split("-").map(&:capitalize).join
  end
end
