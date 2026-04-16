# frozen_string_literal: true

require "open-uri"
require "rubygems/package"
require "zlib"

module BrewDevTools
  class Bottles
    def initialize(shell: Shell.new, stdout: $stdout, archive_fetcher: nil, options: {})
      @shell = shell
      @stdout = stdout
      @formulas = options.fetch(:formulas, [])
      @compare = options.fetch(:compare, false)
      @show_contents = options.fetch(:contents, false)
      @show_urls = options.fetch(:show_urls, false)
      @tag = options[:tag]
      @brew_executable = options.fetch(:brew_executable, ENV.fetch("HOMEBREW_BREW_FILE", "brew"))
      @archive_fetcher = archive_fetcher || method(:fetch_archive_entries)
    end

    def run
      validate_options!
      formulae = fetch_formulae(@formulas)

      return print_compare(formulae.fetch(0), formulae.fetch(1)) if @compare

      formulae.each_with_index do |formula, index|
        @stdout.puts if index.positive?
        print_formula(formula)
      end
    end

    private

    def validate_options!
      raise ValidationError, "Pass at least one formula name." if @formulas.empty?
      raise ValidationError, "--compare expects exactly two formula names." if @compare && @formulas.length != 2
      return unless @show_contents && @tag.to_s.empty?

      raise ValidationError, "--contents requires --tag so a specific bottle can be inspected."
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
      return print_compare_contents(left, right) if @show_contents

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

    def print_formula_contents(formula)
      file = bottle_file_for(formula, @tag)
      entries = @archive_fetcher.call(file.fetch("url"))

      @stdout.puts("#{formula.fetch('full_name')} #{formula_pkg_version(formula)}")
      @stdout.puts("  tag: #{@tag}")
      @stdout.puts("  sha256: #{short_sha(file.fetch('sha256'))}")
      @stdout.puts("  entries: #{entries.length}")
      @stdout.puts("  url: #{file.fetch('url')}") if @show_urls
      entries.each { |entry| @stdout.puts("    #{entry}") }
    end

    def print_compare_contents(left, right)
      left_file = bottle_file_for(left, @tag)
      right_file = bottle_file_for(right, @tag)
      left_entries = @archive_fetcher.call(left_file.fetch("url"))
      right_entries = @archive_fetcher.call(right_file.fetch("url"))

      only_left = left_entries - right_entries
      only_right = right_entries - left_entries
      common = left_entries & right_entries

      @stdout.puts("Compare contents: #{left.fetch('full_name')} #{@tag} <> #{right.fetch('full_name')} #{@tag}")
      @stdout.puts("  common entries: #{common.length}")
      @stdout.puts("  only in #{left.fetch('name')}: #{list_or_none(only_left)}")
      @stdout.puts("  only in #{right.fetch('name')}: #{list_or_none(only_right)}")
      return unless @show_urls

      @stdout.puts("  left url: #{left_file.fetch('url')}")
      @stdout.puts("  right url: #{right_file.fetch('url')}")
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

    def fetch_archive_entries(url)
      URI.open(url, "rb") do |io|
        Zlib::GzipReader.wrap(io) do |gzip|
          Gem::Package::TarReader.new(gzip) do |tar|
            return tar.map(&:full_name).sort
          end
        end
      end
    rescue OpenURI::HTTPError, Zlib::GzipFile::Error, Gem::Package::TarInvalidError => e
      raise CommandError, "Could not inspect bottle contents from #{url}: #{e.message}"
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

    def list_or_none(values)
      values.empty? ? "(none)" : values.join(", ")
    end
  end
end
