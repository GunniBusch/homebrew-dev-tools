# frozen_string_literal: true

require_relative "test_helper"

class CommitSubjectTest < BrewDevToolsTestCase
  def test_new_formula_subject
    suggestion = BrewDevTools::CommitSubject.for_formula(
      formula: "foo",
      base_content: nil,
      final_content: formula_content("foo", "1.2.3"),
      style: :homebrew,
    )

    assert_equal "foo 1.2.3 (new formula)", suggestion.subject
    refute suggestion.generated_summary
  end

  def test_version_bump_subject
    suggestion = BrewDevTools::CommitSubject.for_formula(
      formula: "foo",
      base_content: formula_content("foo", "1.2.2"),
      final_content: formula_content("foo", "1.2.3"),
      style: :homebrew,
    )

    assert_equal "foo 1.2.3", suggestion.subject
    refute suggestion.generated_summary
  end

  def test_fix_subject_falls_back_to_generated_summary
    suggestion = BrewDevTools::CommitSubject.for_formula(
      formula: "foo",
      base_content: formula_content("foo", "1.2.2"),
      final_content: formula_content("foo", "1.2.2", body: "depends_on \"bar\"\n"),
      style: :homebrew,
    )

    assert_equal "foo: update formula", suggestion.subject
    assert suggestion.generated_summary
  end

  def test_conventional_new_formula_subject
    suggestion = BrewDevTools::CommitSubject.for_formula(
      formula: "foo",
      base_content: nil,
      final_content: formula_content("foo", "1.2.3"),
      style: :conventional,
    )

    assert_equal "feat(foo): add new formula 1.2.3", suggestion.subject
  end

  def test_conventional_version_bump_subject
    suggestion = BrewDevTools::CommitSubject.for_formula(
      formula: "foo",
      base_content: formula_content("foo", "1.2.2"),
      final_content: formula_content("foo", "1.2.3"),
      style: :conventional,
    )

    assert_equal "chore(foo): update to 1.2.3", suggestion.subject
  end

  def test_conventional_fix_subject
    suggestion = BrewDevTools::CommitSubject.for_formula(
      formula: "foo",
      base_content: formula_content("foo", "1.2.2"),
      final_content: formula_content("foo", "1.2.2", body: "depends_on \"bar\"\n"),
      style: :conventional,
    )

    assert_equal "fix(foo): update formula", suggestion.subject
    assert suggestion.generated_summary
  end
end
