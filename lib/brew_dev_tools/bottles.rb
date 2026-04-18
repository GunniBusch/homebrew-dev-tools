# frozen_string_literal: true

require "digest"
require "rubygems/package"
require "tmpdir"
require "zlib"

module BrewDevTools
  class Bottles
    ManifestEntry = Struct.new(:name, :type, :digest, :size, :linkname, keyword_init: true)

    def initialize(shell: Shell.new, stdout: $stdout, archive_fetcher: nil, diffoscope_runner: nil, options: {})
      @shell = shell
      @stdout = stdout
      @formulas = options.fetch(:formulas, [])
      @compare = options.fetch(:compare, false)
      @show_contents = options.fetch(:contents, false)
      @show_urls = options.fetch(:show_urls, false)
      @tag = options[:tag]
      @against_tag = options[:against_tag]
      @brew_executable = options.fetch(:brew_executable, "brew")
      @diffoscope_executable = options.fetch(:diffoscope_executable, "diffoscope")
      @archive_fetcher = archive_fetcher || method(:read_archive_manifest)
      @diffoscope_runner = diffoscope_runner || method(:run_diffoscope)
    end

    def run
      validate_options!
      formulae = fetch_formulae(@formulas)

      return print_compare_same_formula(formulae.fetch(0)) if same_formula_compare?
      return print_compare(formulae.fetch(0), formulae.fetch(1)) if @compare

      formulae.each_with_index do |formula, index|
        @stdout.puts if index.positive?
        print_formula(formula)
      end
    end

    private

    def validate_options!
      raise ValidationError, "Pass at least one formula name." if @formulas.empty?
      raise ValidationError, "--contents requires --tag so a specific bottle can be inspected." if @show_contents && @tag.to_s.empty?
      return unless @compare

      if same_formula_compare?
        return
      end

      valid_cross_formula = @formulas.length == 2
      raise ValidationError, "--compare expects either two formula names or one formula with --tag and --against-tag." unless valid_cross_formula
    end

    def same_formula_compare?
      @compare && @formulas.length == 1 && !@tag.to_s.empty? && !@against_tag.to_s.empty?
    end

    def fetch_formulae(names)
      result = @shell.run!(@brew_executable, "info", "--json=v2", *names)
      payload = JSON.parse(result.stdout)
      formulae = payload.fetch("formulae")

      names.map do |name|
        formulae.find { |formula| formula.fetch("name") == name || formula.fetch("full_name") == name } ||
          raise(ValidationError, "No bottle metadata found for `#{name}`.")
      end
    end

    def print_formula(formula)
      return print_formula_contents(formula) if @show_contents

      bottle = stable_bottle(formula)
      @stdout.puts("#{formula.fetch('full_name')} #{formula_pkg_version(formula)}")

      unless bottle
        @stdout.puts("  No stable bottle metadata.")
        return
      end

      files = bottle.fetch("files", {})
      @stdout.puts("  root_url: #{bottle.fetch('root_url')}")
      @stdout.puts("  rebuild: #{bottle.fetch('rebuild')}")
      @stdout.puts("  tags:    #{files.keys.sort.join(', ')}")
      files.keys.sort.each do |tag|
        file = files.fetch(tag)
        @stdout.puts("  #{tag}: cellar=#{file.fetch('cellar')} sha256=#{short_sha(file.fetch('sha256'))}")
        @stdout.puts("    url=#{file.fetch('url')}") if @show_urls
      end
    end

    def print_compare(left, right)
      return print_compare_contents(left, right, @tag, @tag) if @show_contents

      left_bottle = stable_bottle(left)
      right_bottle = stable_bottle(right)

      @stdout.puts("Compare: #{left.fetch('full_name')} #{formula_pkg_version(left)} <> #{right.fetch('full_name')} #{formula_pkg_version(right)}")

      if left_bottle.nil? || right_bottle.nil?
        @stdout.puts("  Bottle availability: #{left.fetch('full_name')}=#{left_bottle ? 'yes' : 'no'}, #{right.fetch('full_name')}=#{right_bottle ? 'yes' : 'no'}")
        return
      end

      @stdout.puts("  rebuild: #{left_bottle.fetch('rebuild')} <> #{right_bottle.fetch('rebuild')}")
      @stdout.puts("  root_url: #{left_bottle.fetch('root_url')} <> #{right_bottle.fetch('root_url')}")

      left_files = left_bottle.fetch("files", {})
      right_files = right_bottle.fetch("files", {})
      left_tags = left_files.keys.sort
      right_tags = right_files.keys.sort
      common_tags = left_tags & right_tags

      @stdout.puts("  only in #{left.fetch('name')}: #{list_or_none(left_tags - right_tags)}")
      @stdout.puts("  only in #{right.fetch('name')}: #{list_or_none(right_tags - left_tags)}")

      differing = common_tags.filter_map do |tag|
        left_file = left_files.fetch(tag)
        right_file = right_files.fetch(tag)
        differences = []
        differences << "cellar #{left_file.fetch('cellar')} <> #{right_file.fetch('cellar')}" if left_file.fetch("cellar") != right_file.fetch("cellar")
        differences << "sha256 #{short_sha(left_file.fetch('sha256'))} <> #{short_sha(right_file.fetch('sha256'))}" if left_file.fetch("sha256") != right_file.fetch("sha256")
        differences << "url differs" if left_file.fetch("url") != right_file.fetch("url")
        next if differences.empty?

        [tag, differences]
      end

      if differing.empty?
        @stdout.puts("  common tags: identical bottle metadata")
      else
        @stdout.puts("  common tags with differences:")
        differing.each do |tag, differences|
          @stdout.puts("    #{tag}: #{differences.join('; ')}")
        end
      end
    end

    def print_compare_same_formula(formula)
      return print_compare_contents(formula, formula, @tag, @against_tag) if @show_contents

      left_file = bottle_file_for(formula, @tag)
      right_file = bottle_file_for(formula, @against_tag)

      @stdout.puts("Compare tags: #{formula.fetch('full_name')} #{formula_pkg_version(formula)}")
      @stdout.puts("  #{@tag} <> #{@against_tag}")
      @stdout.puts("  cellar: #{left_file.fetch('cellar')} <> #{right_file.fetch('cellar')}")
      @stdout.puts("  sha256: #{short_sha(left_file.fetch('sha256'))} <> #{short_sha(right_file.fetch('sha256'))}")
      @stdout.puts("  urls differ: #{left_file.fetch('url') != right_file.fetch('url')}")
    end

    def print_formula_contents(formula)
      file = bottle_file_for(formula, @tag)
      manifest = archive_manifest_for(formula, @tag)

      @stdout.puts("#{formula.fetch('full_name')} #{formula_pkg_version(formula)}")
      @stdout.puts("  tag: #{@tag}")
      @stdout.puts("  sha256: #{short_sha(file.fetch('sha256'))}")
      @stdout.puts("  entries: #{manifest.length}")
      @stdout.puts("  url: #{file.fetch('url')}") if @show_urls
      manifest.each { |entry| @stdout.puts("    #{entry.name}") }
    end

    def print_compare_contents(left_formula, right_formula, left_tag, right_tag)
      left_file = bottle_file_for(left_formula, left_tag)
      right_file = bottle_file_for(right_formula, right_tag)
      left_manifest = archive_manifest_for(left_formula, left_tag)
      right_manifest = archive_manifest_for(right_formula, right_tag)

      left_index = left_manifest.to_h { |entry| [entry.name, entry] }
      right_index = right_manifest.to_h { |entry| [entry.name, entry] }
      left_names = left_index.keys.sort
      right_names = right_index.keys.sort
      common_names = left_names & right_names

      only_left = left_names - right_names
      only_right = right_names - left_names
      changed = common_names.filter_map do |name|
        left_entry = left_index.fetch(name)
        right_entry = right_index.fetch(name)
        differences = []
        differences << "type #{left_entry.type} <> #{right_entry.type}" if left_entry.type != right_entry.type
        differences << "size #{left_entry.size} <> #{right_entry.size}" if left_entry.size != right_entry.size
        differences << "digest #{short_sha_or_nil(left_entry.digest)} <> #{short_sha_or_nil(right_entry.digest)}" if left_entry.digest != right_entry.digest
        differences << "link #{left_entry.linkname} <> #{right_entry.linkname}" if left_entry.linkname != right_entry.linkname
        next if differences.empty?

        [name, differences]
      end

      @stdout.puts("Compare contents: #{left_formula.fetch('full_name')} #{left_tag} <> #{right_formula.fetch('full_name')} #{right_tag}")
      @stdout.puts("  archive entries match: #{changed.empty? && only_left.empty? && only_right.empty?}")
      if left_formula.fetch("full_name") == right_formula.fetch("full_name")
        @stdout.puts("  all bottle candidate: #{changed.empty? && only_left.empty? && only_right.empty? ? 'yes' : 'no'}")
      end
      @stdout.puts("  common entries: #{common_names.length}")
      @stdout.puts("  only in #{tag_label(left_formula, left_tag, right_formula)}: #{list_or_none(only_left)}")
      @stdout.puts("  only in #{tag_label(right_formula, right_tag, left_formula)}: #{list_or_none(only_right)}")

      if changed.empty?
        @stdout.puts("  changed entries: (none)")
      else
        @stdout.puts("  changed entries:")
        changed.each do |name, differences|
          @stdout.puts("    #{name}: #{differences.join('; ')}")
        end
      end

      print_diffoscope(left_formula, left_tag, right_tag) if left_formula.fetch("full_name") == right_formula.fetch("full_name")

      return unless @show_urls

      @stdout.puts("  left url: #{left_file.fetch('url')}")
      @stdout.puts("  right url: #{right_file.fetch('url')}")
    end

    def tag_label(formula, tag, other_formula)
      formula.fetch("full_name") == other_formula.fetch("full_name") ? tag : formula.fetch("name")
    end

    def archive_manifest_for(formula, tag)
      cache_path = cache_path_for(formula, tag)
      @archive_fetcher.call(cache_path)
    end

    def print_diffoscope(formula, left_tag, right_tag)
      left_path = cache_path_for(formula, left_tag)
      right_path = cache_path_for(formula, right_tag)
      report = @diffoscope_runner.call(left_path, right_path, formula.fetch("name"), left_tag, right_tag)
      return if report.nil?

      @stdout.puts("  diffoscope: #{report.fetch(:summary)}")
      @stdout.puts("  diffoscope report: #{report.fetch(:path)}") if report[:path]
      return if report[:excerpt].to_s.empty?

      @stdout.puts("  diffoscope excerpt:")
      report.fetch(:excerpt).lines.each do |line|
        @stdout.puts("    #{line.rstrip}")
      end
    end

    def cache_path_for(formula, tag)
      formula_name = formula.fetch("full_name")
      cache_path = @shell.run!(
        @brew_executable,
        "--cache",
        "--bottle-tag=#{tag}",
        formula_name,
      ).stdout.strip
      return cache_path if File.exist?(cache_path)

      @shell.run!(
        @brew_executable,
        "fetch",
        "--bottle-tag=#{tag}",
        formula_name,
      )
      cache_path
    end

    def run_diffoscope(left_path, right_path, formula_name, left_tag, right_tag)
      report_path = File.join(
        Dir.tmpdir,
        "brew-bottles-diffoscope-#{formula_name}-#{left_tag}-#{right_tag}.txt",
      )
      result = @shell.run!(
        @diffoscope_executable,
        "--text",
        report_path,
        left_path,
        right_path,
        allow_failure: true,
      )
      report_body = File.exist?(report_path) ? File.read(report_path) : ""
      summary =
        case result.status
        when 0 then "no differences"
        when 1 then "differences detected"
        else "failed with exit #{result.status}"
        end

      {
        summary:,
        path: File.exist?(report_path) ? report_path : nil,
        excerpt: report_body.lines.first(40).join,
      }
    rescue Errno::ENOENT
      { summary: "unavailable", path: nil, excerpt: "" }
    end

    def bottle_file_for(formula, tag)
      bottle = stable_bottle(formula)
      raise ValidationError, "No stable bottle metadata found for `#{formula.fetch('full_name')}`." if bottle.nil?

      files = bottle.fetch("files", {})
      return files.fetch(tag) if files.key?(tag)

      available = files.keys.sort
      raise ValidationError,
            "Bottle tag `#{tag}` not found for `#{formula.fetch('full_name')}`. Available tags: #{list_or_none(available)}"
    end

    def read_archive_manifest(path)
      File.open(path, "rb") do |io|
        Zlib::GzipReader.wrap(io) do |gzip|
          Gem::Package::TarReader.new(gzip) do |tar|
            return tar.map { |entry| manifest_entry_for(entry) }.sort_by(&:name)
          end
        end
      end
    rescue Errno::ENOENT, Zlib::GzipFile::Error, Gem::Package::TarInvalidError => e
      raise CommandError, "Could not inspect bottle contents from #{path}: #{e.message}"
    end

    def manifest_entry_for(entry)
      ManifestEntry.new(
        name: entry.full_name,
        type: entry.header.typeflag,
        digest: digest_for(entry),
        size: entry.header.size,
        linkname: entry.header.linkname,
      )
    end

    def digest_for(entry)
      return nil unless entry.file?

      Digest::SHA256.hexdigest(entry.read)
    end

    def stable_bottle(formula)
      formula.dig("bottle", "stable")
    end

    def formula_pkg_version(formula)
      stable = formula.dig("versions", "stable")
      revision = formula.fetch("revision")
      return stable if revision.to_i.zero?

      "#{stable}_#{revision}"
    end

    def short_sha(sha)
      sha[0, 12]
    end

    def short_sha_or_nil(sha)
      sha.nil? ? "(none)" : short_sha(sha)
    end

    def list_or_none(values)
      values.empty? ? "(none)" : values.join(", ")
    end
  end
end
