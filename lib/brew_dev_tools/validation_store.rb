# frozen_string_literal: true

module BrewDevTools
  class ValidationStore
    def self.save(repo:, report:)
      dir = File.join(repo.git_dir, "brew-dev-tools")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "wwdd-last.json"), JSON.pretty_generate(report))
    end

    def self.load(repo:)
      path = File.join(repo.git_dir, "brew-dev-tools", "wwdd-last.json")
      return nil unless File.exist?(path)

      JSON.parse(File.read(path))
    end
  end
end
