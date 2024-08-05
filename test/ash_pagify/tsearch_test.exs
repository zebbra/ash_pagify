defmodule AshPagify.TsearchTest do
  @moduledoc false

  use ExUnit.Case

  alias AshPagify.Factory.Comment

  require Ash.Query

  doctest AshPagify.Tsearch, import: true

  describe "merge_opts/1" do
    test "merges default options with global options" do
      assert AshPagify.Tsearch.merge_opts() == [
               negation: true,
               prefix: true,
               any_word: false,
               tsvector_column: nil
             ]
    end

    test "merges resource based options if defined" do
      assert AshPagify.Tsearch.merge_opts(for: Comment) == [
               negation: true,
               prefix: false,
               any_word: true,
               tsvector_column: Ash.Query.expr(custom_tsvector)
             ]
    end
  end

  describe "tsvector/1" do
    test "returns default tsvector if no options are provided" do
      assert AshPagify.Tsearch.tsvector() == Ash.Query.expr(tsvector)
    end

    test "returns default tsvector if custom tsvector is passed but now tsvector_column is defined" do
      opts = [
        full_text_search: [
          tsvector: :custom,
          tsvector_column: nil
        ]
      ]

      assert AshPagify.Tsearch.tsvector(opts) == Ash.Query.expr(tsvector)
    end

    test "returns default tsvector if custom tsvector is passed and tsvector_column is []" do
      opts = [
        full_text_search: [
          tsvector: :custom,
          tsvector_column: []
        ]
      ]

      assert AshPagify.Tsearch.tsvector(opts) == Ash.Query.expr(tsvector)
    end

    test "returns tsvector_column if no custom tsvector is specified but tsvector_column is configured" do
      opts = [
        full_text_search: [
          tsvector_column: Ash.Query.expr(custom_tsvector)
        ]
      ]

      assert AshPagify.Tsearch.tsvector(opts) == Ash.Query.expr(custom_tsvector)
    end

    test "returns default tsvector if custom tsvector is not passed and tsvector_column is configured but it is a list" do
      opts = [
        full_text_search: [
          tsvector_column: [
            custom: Ash.Query.expr(custom_tsvector)
          ]
        ]
      ]

      assert AshPagify.Tsearch.tsvector(opts) == Ash.Query.expr(tsvector)
    end

    test "returns custom tsvector from tsvector_column list" do
      opts = [
        full_text_search: [
          tsvector: :custom,
          tsvector_column: [
            custom: Ash.Query.expr(custom_tsvector)
          ]
        ]
      ]

      assert AshPagify.Tsearch.tsvector(opts) == Ash.Query.expr(custom_tsvector)
    end

    test "returns custom tsvector from tsvector_column list with string key" do
      opts = [
        full_text_search: [
          tsvector: "custom",
          tsvector_column: [
            custom: Ash.Query.expr(custom_tsvector)
          ]
        ]
      ]

      assert AshPagify.Tsearch.tsvector(opts) == Ash.Query.expr(custom_tsvector)
    end

    test "returns default tsvector if tsvector_column list and key is configured but do not match" do
      opts = [
        full_text_search: [
          tsvector: :custom_not_existing,
          tsvector_column: [
            custom: Ash.Query.expr(custom_tsvector)
          ]
        ]
      ]

      assert AshPagify.Tsearch.tsvector(opts) == Ash.Query.expr(tsvector)
    end
  end

  describe "query_terms/1" do
    test "splits search string into terms" do
      assert AshPagify.Tsearch.query_terms("term1 term2") == ["term1", "term2"]
    end

    test "trims terms" do
      assert AshPagify.Tsearch.query_terms(" term1  term2 ") == ["term1", "term2"]
    end

    test "filters out empty terms" do
      assert AshPagify.Tsearch.query_terms("term1  term2 ") == ["term1", "term2"]
    end
  end

  describe "sanitize_term/2" do
    test "negated term and negation false gives not negated with non-altered term" do
      assert AshPagify.Tsearch.sanitize_term("!term", false) == {false, "!term"}
    end

    test "non-negated term and negation false gives not negated with non-altered term" do
      assert AshPagify.Tsearch.sanitize_term("term", false) == {false, "term"}
    end

    test "negated term and negation true gives negated with altered term" do
      assert AshPagify.Tsearch.sanitize_term("!term", true) == {true, "term"}
    end

    test "non-negated term and negation true gives not negated with non-altered term" do
      assert AshPagify.Tsearch.sanitize_term("term", true) == {false, "term"}
    end
  end

  describe "normalize/1" do
    test "removes disallowed characters" do
      assert AshPagify.Tsearch.normalize("term?") == "term "
    end

    test "handles unicode characters correctly" do
      assert AshPagify.Tsearch.normalize("hürl.") == "hürl."
    end
  end

  describe "tsquery_expression/3" do
    test "returns simple term" do
      assert AshPagify.Tsearch.tsquery_expression("term",
               negated: false,
               prefix: false
             ) ==
               "term"
    end

    test "returns term with negation" do
      assert AshPagify.Tsearch.tsquery_expression("term",
               negated: true,
               prefix: false
             ) ==
               "!(term)"
    end

    test "returns term with prefix" do
      assert AshPagify.Tsearch.tsquery_expression("term",
               negated: false,
               prefix: true
             ) ==
               "term:*"
    end

    test "returns term with negation and prefix" do
      assert AshPagify.Tsearch.tsquery_expression("term",
               negated: true,
               prefix: true
             ) ==
               "!(term:*)"
    end
  end

  describe "tsquery_for_term/1" do
    test "removes disallowed characters and negates term" do
      assert AshPagify.Tsearch.tsquery_for_term("!term?", negation: true) ==
               "!(term )"
    end

    test "remvoes disallowed characters and does not negate term" do
      assert AshPagify.Tsearch.tsquery_for_term("!term?") ==
               "!term "
    end

    test "adds prefix to term" do
      assert AshPagify.Tsearch.tsquery_for_term("term?", prefix: true) ==
               "term :*"
    end

    test "all features combined" do
      assert AshPagify.Tsearch.tsquery_for_term("!term?",
               negation: true,
               prefix: true
             ) ==
               "!(term :*)"
    end
  end

  describe "tsquery/1" do
    test "returns empty quoted string in case of nil" do
      assert AshPagify.Tsearch.tsquery(nil) == "''"
    end

    test "returns empty quoted string in case of blank" do
      assert AshPagify.Tsearch.tsquery("") == "''"
    end

    test "returns tsquery expression with prefix for single term" do
      assert AshPagify.Tsearch.tsquery("term") == "term:*"
    end

    test "does not add prefix if it is set to false" do
      assert AshPagify.Tsearch.tsquery("term", full_text_search: [prefix: false]) == "term"
    end

    test "returns tsquery expression for multiple terms with and combinator and prefix" do
      assert AshPagify.Tsearch.tsquery("term1 term2") ==
               "term1:* & term2:*"
    end

    test "returns tsquery expression for multiple terms with or combinator in case any_word is configured" do
      assert AshPagify.Tsearch.tsquery("term1 term2", full_text_search: [any_word: true]) ==
               "term1:* | term2:*"
    end

    test "all combinations" do
      assert AshPagify.Tsearch.tsquery("!term1 term2?",
               full_text_search: [
                 any_word: true
               ]
             ) ==
               "!(term1:*) | term2 :*"
    end
  end
end
