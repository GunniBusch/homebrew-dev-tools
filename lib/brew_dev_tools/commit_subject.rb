# frozen_string_literal: true

module BrewDevTools
  class CommitSubject
    Suggestion = Struct.new(:subject, :kind, :generated_summary, keyword_init: true)
    VALID_STYLES = [:homebrew, :conventional].freeze
    TEMPLATES = {
      homebrew: {
        new_formula: "%<formula>s %<version>s (new formula)",
        version_bump: "%<formula>s %<version>s",
        formula_fix: "%<formula>s: update formula",
      },
      conventional: {
        new_formula: "feat(%<formula>s): add new formula %<version>s",
        version_bump: "chore(%<formula>s): update to %<version>s",
        formula_fix: "fix(%<formula>s): update formula",
      },
    }.freeze

    ALLOWED_VERSION_BUMP_PREFIXES = /\A\s*(url|sha256|version|mirror)\b/.freeze

    def self.templates_for(style)
      validate_style!(style)
      TEMPLATES.fetch(style).dup
    end

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
      template = templates_for(style).fetch(:new_formula)
      subject = if version
        format(template, formula: formula, version: version)
      elsif style == :homebrew
        "#{formula} new formula (new formula)"
      else
        "feat(#{formula}): add new formula"
      end

      Suggestion.new(
        subject: subject,
        kind: :new_formula,
        generated_summary: false,
      )
    end

    def self.version_bump_suggestion(formula:, version:, style:)
      subject = if version
        format(templates_for(style).fetch(:version_bump), formula: formula, version: version)
      elsif style == :homebrew
        "#{formula} update formula version"
      else
        "chore(#{formula}): update formula version"
      end

      Suggestion.new(
        subject: subject,
        kind: :version_bump,
        generated_summary: false,
      )
    end

    def self.formula_fix_suggestion(formula:, style:)
      Suggestion.new(
        subject: format(templates_for(style).fetch(:formula_fix), formula: formula),
        kind: :formula_fix,
        generated_summary: true,
      )
    end

    private_class_method :changed_lines
    private_class_method :validate_style!, :new_formula_suggestion, :version_bump_suggestion, :formula_fix_suggestion
  end
end
