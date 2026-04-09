# frozen_string_literal: true

module BrewDevTools
  class CommitSubject
    Suggestion = Struct.new(:subject, :kind, :generated_summary, keyword_init: true)

    ALLOWED_VERSION_BUMP_PREFIXES = /\A\s*(url|sha256|version|mirror)\b/.freeze

    def self.for_formula(formula:, base_content:, final_content:)
      final_version = FormulaInspector.extract_version(final_content)

      if base_content.nil?
        version = final_version || "new formula"
        return Suggestion.new(
          subject: "#{formula} #{version} (new formula)",
          kind: :new_formula,
          generated_summary: false,
        )
      end

      if pure_version_bump?(base_content: base_content, final_content: final_content)
        return Suggestion.new(
          subject: "#{formula} #{FormulaInspector.extract_version(final_content)}",
          kind: :version_bump,
          generated_summary: false,
        )
      end

      Suggestion.new(
        subject: "#{formula}: update formula",
        kind: :formula_fix,
        generated_summary: true,
      )
    end

    def self.pure_version_bump?(base_content:, final_content:)
      base_version = FormulaInspector.extract_version(base_content)
      final_version = FormulaInspector.extract_version(final_content)
      return false if base_version.nil? || final_version.nil? || base_version == final_version

      changed_lines = changed_lines(base_content, final_content)
      return false if changed_lines.empty?

      changed_lines.all? do |line|
        line.strip.empty? || line.match?(ALLOWED_VERSION_BUMP_PREFIXES)
      end
    end

    def self.changed_lines(base_content, final_content)
      old_lines = base_content.lines.map(&:chomp)
      new_lines = final_content.lines.map(&:chomp)
      (old_lines - new_lines) + (new_lines - old_lines)
    end

    private_class_method :changed_lines
  end
end
