# frozen_string_literal: true

module BrewDevTools
  module FormulaInspector
    module_function

    def formula_path?(path)
      path.match?(%r{\AFormula/(?:[^/]+/)*[^/]+\.rb\z})
    end

    def formula_name_from_path(path)
      File.basename(path, ".rb")
    end

    def matching_formula_paths(name, paths)
      paths.select { |path| formula_name_from_path(path) == name }
    end

    def extract_version(content)
      return nil if content.nil? || content.empty?

      explicit = content[/^\s*version\s+"([^"]+)"/, 1]
      return explicit if explicit

      url = content[/^\s*url\s+"([^"]+)"/, 1]
      return nil unless url

      version_from_url(url)
    end

    def version_from_url(url)
      basename = File.basename(url)
      basename = basename.sub(/\.(tar\.gz|tar\.bz2|tar\.xz|tgz|tbz|txz|zip|gem)\z/i, "")
      basename[/(\d+\.\d+(?:\.\d+)*[-_0-9A-Za-z.]*)/, 1]
    end
  end
end
