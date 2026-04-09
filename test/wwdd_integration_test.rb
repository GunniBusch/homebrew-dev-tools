# frozen_string_literal: true

require_relative "test_helper"

class WwddIntegrationTest < BrewDevToolsTestCase
  def test_runs_new_formula_validation_steps_in_order
    with_tmpdir do |dir|
      init_repo(dir)
      remote = init_bare_remote(dir)
      attach_origin(dir, remote)
      commit_formula(dir, "foo", formula_content("foo", "1.0.0"), "foo 1.0.0 (new formula)")
      run_cmd(dir, "git", "push", "-u", "origin", "master")
      run_cmd(dir, "git", "checkout", "-b", "feature")
      File.write(dir/"Formula/bar.rb", formula_content("bar", "2.0.0"))

      fake_bin = dir.parent/"#{dir.basename}-fake-bin"
      FileUtils.mkdir_p(fake_bin)
      log_file = dir/"brew.log"
      File.write(
        fake_bin/"brew",
        <<~SH,
          #!/bin/sh
          echo "$@" >> "#{log_file}"
          exit 0
        SH
      )
      FileUtils.chmod("+x", fake_bin/"brew")

      shell = BrewDevTools::Shell.new(env: { "PATH" => "#{fake_bin}:#{ENV.fetch('PATH')}" })
      repo = BrewDevTools::GitRepo.new(path: dir, shell: shell)

      BrewDevTools::Wwdd.new(
        repo: repo,
        shell: shell,
        stdout: StringIO.new,
        options: { brew_executable: "brew" },
      ).run

      logged = File.read(log_file).lines.map(&:strip)
      assert_equal [
        "style --fix --formula bar",
        "install --build-from-source bar",
        "test bar",
        "audit --new bar",
      ], logged

      report = BrewDevTools::ValidationStore.load(repo: repo)
      assert_equal "bar", report.fetch("formulas").first.fetch("formula")
    end
  end

  def test_runs_strict_audit_for_existing_formula
    with_tmpdir do |dir|
      init_repo(dir)
      remote = init_bare_remote(dir)
      attach_origin(dir, remote)
      commit_formula(dir, "foo", formula_content("foo", "1.0.0"), "foo 1.0.0 (new formula)")
      run_cmd(dir, "git", "push", "-u", "origin", "master")
      run_cmd(dir, "git", "checkout", "-b", "feature")
      File.write(dir/"Formula/foo.rb", formula_content("foo", "1.0.1"))

      fake_bin = dir.parent/"#{dir.basename}-fake-bin"
      FileUtils.mkdir_p(fake_bin)
      log_file = dir/"brew.log"
      File.write(
        fake_bin/"brew",
        <<~SH,
          #!/bin/sh
          echo "$@" >> "#{log_file}"
          exit 0
        SH
      )
      FileUtils.chmod("+x", fake_bin/"brew")

      shell = BrewDevTools::Shell.new(env: { "PATH" => "#{fake_bin}:#{ENV.fetch('PATH')}" })
      repo = BrewDevTools::GitRepo.new(path: dir, shell: shell)

      BrewDevTools::Wwdd.new(
        repo: repo,
        shell: shell,
        stdout: StringIO.new,
        options: { brew_executable: "brew", online: true },
      ).run

      logged = File.read(log_file)
      assert_includes logged, "audit --strict --online foo"
    end
  end
end
