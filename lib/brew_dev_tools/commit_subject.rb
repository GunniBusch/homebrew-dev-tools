# frozen_string_literal: true

module BrewDevTools
  class CommitSubject
    Suggestion = Struct.new(:subject, :kind, :generated_summary, keyword_init: true)
    VALID_STYLES = [:homebrew, :conventional].freeze

    ALLOWED_VERSION_BUMP_PREFIXES = /\A\s*(url|sha256|version|mirror)\b/.freeze

    def self.for_formula(formula:, base_content:, final_content:, style:)
      validate_style!(style)
      final_version = FormulaInspector.extract_version(final_content)

      if base_content.nil?
        return new_formula_suggestion(formula: formula, version: final_version, style: style)
      end

      if pure_version_bump?(base_content: base_content, final_content: final_content)
        return version_bump_suggestion(formula: formula, version: final_version, style: style)
      end

      formula_fix_suggestion(formula: formula, style: style)
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

    def self.validate_style!(style)
      return if VALID_STYLES.include?(style)

      raise ValidationError, "Unsupported commit style `#{style}`. Use one of: #{VALID_STYLES.join(', ')}"
    end

    def self.new_formula_suggestion(formula:, version:, style:)
      if style == :homebrew
        version_label = version || "new formula"
        return Suggestion.new(
          subject: "#{formula} #{version_label} (new formula)",
          kind: :new_formula,
          generated_summary: false,
        )
      end

      description = version ? "add new formula #{version}" : "add new formula"
      Suggestion.new(
        subject: "feat(#{formula}): #{description}",
        kind: :new_formula,
        generated_summary: false,
      )
    end

    def self.version_bump_suggestion(formula:, version:, style:)
      if style == :homebrew
        return Suggestion.new(
          subject: "#{formula} #{version}",
          kind: :version_bump,
          generated_summary: false,
        )
      end

      description = version ? "update to #{version}" : "update formula version"
      Suggestion.new(
        subject: "chore(#{formula}): #{description}",
        kind: :version_bump,
        generated_summary: false,
      )
    end

    def self.formula_fix_suggestion(formula:, style:)
      subject = if style == :homebrew
        "#{formula}: update formula"
      else
        "fix(#{formula}): update formula"
      end

      Suggestion.new(
        subject: subject,
        kind: :formula_fix,
        generated_summary: true,
      )
    end

    private_class_method :changed_lines
    private_class_method :validate_style!, :new_formula_suggestion, :version_bump_suggestion, :formula_fix_suggestion
  end
end
