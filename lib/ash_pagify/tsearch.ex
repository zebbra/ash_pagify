defmodule AshPagify.Tsearch do
  @moduledoc """
  AshPagify full-text search utilities.

  This module provides utilities for full-text search in AshPagify. For a basic usage
  you can `use AshPagify.Tsearch` and implement the `tsvector` calculation in your
  resource.

  ```elixir
  defmodule MyApp.Resource do
    use AshPagify.Tsearch
    require Ash.Query

    calculations do
      calculate :tsvector,
        AshPostgres.Tsvector,
          expr(
            fragment("to_tsvector('simple', coalesce(?, '')) || to_tsvector('simple', coalesce(?, ''))",
            name,
            title
          )
        )
      end
    end
  end
  ```

  AshPagify.Tsearch provides the following calculations which are used by `AshPagify.search` for full-text search:

  - `:tsquery` - The tsquery to search for.
  - `:full_text_search` - A boolean indicating whether the tsvector matches the tsquery.
  - `:full_text_search_rank` - The rank of the tsvector against the tsquery.

  If you need to provide a custom implementation for one of these calculations, you can do so by
  1. not require the calculation in your resource
  2. implementing the calculation in your resource

  ```elixir
  defmodule MyApp.Resource do
    use AshPagify.Tsearch, only: [:full_text_search, :full_text_search_rank]
    require Ash.Query

    calculations do
      calculate :tsquery,
        AshPostgres.Tsquery,
          # use english dictionary unaccent PostgreSQL extension
          expr(fragment("to_tsquery('english', unaccent(?))", ^arg(:search)))
        )
      end

      ...
    end
  end
  ```

  ## Installation

  If you do not use any PostgreSQL specific full-text search extensions, you can skip this step.

  Otherwise, you need to add the required extensions to your Repo.installed_extensions list.

  ```elixir
  defmodule MyApp.Repo do
    use AshPostgres.Repo, otp_app: :my_app

    def installed_extensions do
      ["ash-functions", "uuid-ossp", "citext", "unaccent", AshUUID.PostgresExtension]
    end
  end
  ```

  ## Configuration

  You can configure the full-text search options globally, per resource, or locally.
  The options are merged in the following order:

  1. Function arguments (highest priority)
  2. Resource-level options (set in the resource module)
  3. Global options in the application environment (set in config files)
  4. Library defaults (lowest priority)

  Have a look at `t:tsearch_option/0` for a list of available options.

  ## Features

  ### :prefix (PostgreSQL 8.4 and newer only)

  PostgreSQL's full text search matches on whole words by default. If you want to search for partial words,
  however, you can set :prefix to true in one of the configuration options described above.

  Default: `true`

  ### :negation

  PostgreSQL's full text search matches all search terms by default. If you want to exclude certain words,
  you can set :negation to true. Then any term that begins with an exclamation point `!` will be excluded
  from the results.

  Default: `true`

  ### :any_word

  Setting this attribute to true will perform a search which will return all models containing any word
  in the search terms. If set to false, the search will return all models containing all words in the
  search terms.

  Default: `false`

  ### :tsvector_column

  This option allows you to specify a custom tsvector column expression for dynamic tsvector column lookup.
  Have a look at the `Enhanced search` section for more information.

  Default: `nil`

  ### :dictionary

  We do not provide a mechanisme to set the dictionary in the configuration options. You can set the dictionary
  in a custom `tsquery` calculation implementation in your resource.

  ### :weighting

  We do not provide a mechanisme to set the weighting in the configuration options. You can set the weighting
  in your `tsvector` calculation implementation in your resource (or in the tsvector column in your database).

  ## Enhanced search

  If you need to be able to change the `tsvector` column dynamically (e.g. based on some user input), you can
  use the `:tsvector_column` option. This option should be specified in your resource module. Then you need
  to pass the targeted tsvector calculation as `full_text_search: [tsvector: :custom_tsvector]` option to your
  `AshPagify.validate_and_run/4` call (or other functions provided by AshPagify). This approach is mandatory so we
  can serialize the custom tsvector in `AshPagify.query_to_filters_map` and restore it in `AshPagify.query_for_filters_map`
  accordingly.

  ```elixir
  defmodule MyApp.Resource do
    use AshPagify.Tsearch
    require Ash.Query

    def full_text_search do
      [
        tsvector_column: [
          custom_tsvector: Ash.Query.expr(custom_tsvector),
          another_custom_tsvector: Ash.Query.expr(another_custom_tsvector),
        ]
      ]
    end

    calculations do
      # default tsvector calculation
      calculate :tsvector,
        AshPostgres.Tsvector,
          expr(
            fragment("to_tsvector('simple', coalesce(?, '')) || to_tsvector('simple', coalesce(?, ''))",
            name,
            title
          )
        )
      end

      # custom tsvector calculation
      calculate :custom_tsvector,
        AshPostgres.Tsvector,
          expr(
            fragment("to_tsvector('simple', coalesce(?, ''))",
            name
          )
        )
      end

      # another custom tsvector calculation
      calculate :another_custom_tsvector,
        AshPostgres.Tsvector,
          expr(
            fragment("to_tsvector('simple', coalesce(?, ''))",
            title
          )
        )
      end
    end
  end
  ```

  The in your business logic:

  ```elixir
  def search(query, opts \\\\ []) do
    opts = AshPagify.set_tsvector(:custom_tsvector, opts)
    query
    |> AshPagify.validate_and_run(MyApp.Resource, opts)
  end
  ```
  """

  alias AshPagify.Misc

  require Ash.Query

  @disallowed_tsquery_characters ~r/['?\\:‘’ʻʼ\|\&]/u

  @typedoc """
  A list of options for full text search.

  - `:negation` - Whether to negate the search. Defaults to `true`.
  - `:prefix` - Whether to prefix the search. Defaults to `true`.
  - `:any_word` - Whether to combine multiple words with || or &&. Defaults to `false` (&&).
  - `:tsvector_column` - Custom tsvector column expressions for dynamic tsvector
    column lookup. Defaults to `nil`.
  """
  @type tsearch_option ::
          {:negation, boolean()}
          | {:prefix, boolean()}
          | {:any_word, boolean()}
          | {:tsvector_column, Ash.Expr.t() | list(Ash.Expr.t())}

  @doc """
  Returns the default full text search options.

  The default options are:
  - `:negation` - `true`
  - `:prefix` - `true`
  - `:any_word` - `false`
  - `:tsvector_column` - `nil`
  """
  @spec default_opts() :: [tsearch_option()]
  def default_opts do
    [
      negation: true,
      prefix: true,
      any_word: false,
      tsvector_column: nil
    ]
  end

  @dynamic_opts [:search, :tsvector, :tsvector_column]

  @doc """
  Returns the keys for the full text search options.
  """
  def option_keys do
    Enum.map(default_opts(), &elem(&1, 0)) ++ @dynamic_opts
  end

  @doc """
  Merges the given options with the default options.

  The options are merged in the following order:

  1. Function arguments (highest priority)
  2. Resource-level options (set in the resource module)
  3. Global options in the application environment (set in config files)
  4. Library defaults (lowest priority)
  """
  def merge_opts(opts \\ []) do
    default_opts()
    |> Misc.list_merge(Misc.get_global_opts(:full_text_search))
    |> Misc.list_merge(resource_option(Keyword.get(opts, :for)))
    |> Misc.list_merge(Keyword.get(opts, :full_text_search, []))
  end

  defp resource_option(resource) when is_atom(resource) and resource != nil do
    if Keyword.has_key?(resource.__info__(:functions), :full_text_search) do
      resource.full_text_search()
    else
      []
    end
  end

  defp resource_option(_), do: []

  @doc """
  Returns the tsvector expression for the given options.

  Respects the `:tsvector_column` option together with the `:tsvector` option.
  If both are set, the `:tsvector` option is used to lookup the tsvector column
  in the `:tsvector_column` option. If the custom tsvector column is not found,
  the default tsvector column is used.
  """
  def tsvector(opts \\ []) do
    full_text_search = merge_opts(opts)

    tsvector = Keyword.get(full_text_search, :tsvector)
    tsvector_column = Keyword.get(full_text_search, :tsvector_column)

    coalesce_tsvector(tsvector, tsvector_column)
  end

  defp coalesce_tsvector(nil, nil), do: Ash.Query.expr(tsvector)
  defp coalesce_tsvector(_, nil), do: Ash.Query.expr(tsvector)

  defp coalesce_tsvector(key, tsvector_column) when is_binary(key) and is_list(tsvector_column) do
    coalesce_tsvector(String.to_existing_atom(key), tsvector_column)
  rescue
    ArgumentError -> Ash.Query.expr(tsvector)
  end

  defp coalesce_tsvector(key, tsvector_column) when is_atom(key) and is_list(tsvector_column) do
    Keyword.get(tsvector_column, key, Ash.Query.expr(tsvector))
  end

  defp coalesce_tsvector(nil, tsvector_column) do
    if is_tuple(tsvector_column) or is_list(tsvector_column) do
      Ash.Query.expr(tsvector)
    else
      tsvector_column
    end
  end

  defp coalesce_tsvector(_, _), do: Ash.Query.expr(tsvector)

  @doc """
  Returns the tsquery expression for the given search term and options.

  The search term is split into terms and each term is sanitized and normalized.
  The terms are then combined into a tsquery expression.
  """
  def tsquery(search, opts \\ [])
  def tsquery("", _opts), do: "''"
  def tsquery(nil, _opts), do: "''"

  def tsquery(search, opts) do
    opts = merge_opts(opts)

    tsquery_terms =
      search
      |> query_terms()
      |> Enum.map(&tsquery_for_term(&1, opts))
      |> Enum.reject(&blank?/1)

    if Keyword.get(opts, :any_word, false) do
      Enum.join(tsquery_terms, " | ")
    else
      Enum.join(tsquery_terms, " & ")
    end
  end

  @doc """
  Splits the search term into terms and returns a list of trimmed terms.
  """
  def query_terms(search) do
    search
    |> String.split(~r/\s+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&blank?/1)
  end

  @doc """
  Returns the tsquery expression for the given term and options.
  """
  def tsquery_for_term(unsanitized_term, opts \\ []) do
    {negated, sanitized_term} =
      sanitize_term(unsanitized_term, Keyword.get(opts, :negation, false))

    term_sql = normalize(sanitized_term)

    if String.trim(term_sql) == "" do
      ""
    else
      prefix = Keyword.get(opts, :prefix, false)
      tsquery_expression(term_sql, negated: negated, prefix: prefix)
    end
  end

  @doc """
  Handles the negation of the term.
  """
  def sanitize_term(term, true) do
    negated = String.starts_with?(term, "!")
    term = if negated, do: String.replace_prefix(term, "!", ""), else: term

    {negated, term}
  end

  def sanitize_term(term, false), do: {false, term}

  @doc """
  Replaces disallowed characters in the term with spaces.
  """
  def normalize(term) do
    String.replace(term, @disallowed_tsquery_characters, " ")
  end

  @doc """
  After this, the SQL expression evaluates to a string containing the term surrounded by single-quotes.

  If :prefix is true, then the term will have :* appended to the end.
  If :negated is true, then the term will have ! prepended to the front and be surrounded by brackets.
  """
  def tsquery_expression(term_sql, opts \\ []) do
    negated = Keyword.get(opts, :negated, false)
    prefix = Keyword.get(opts, :prefix, false)

    [
      if(negated, do: "!("),
      term_sql,
      if(prefix, do: ":*"),
      if(negated, do: ")")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join()
  end

  defp blank?(t), do: String.trim(t) == ""

  defmacro __using__(opts \\ []) do
    require Ash.Query

    only = Keyword.get(opts, :only, [])

    quote do
      if unquote(only) == [] or :full_text_search in unquote(only) do
        calculations do
          calculate :full_text_search,
                    :boolean,
                    expr(fragment("(? @@ ?)", ^arg(:tsvector), ^arg(:tsquery))) do
            argument :tsvector, AshPostgres.Tsvector, allow_expr?: true, allow_nil?: false
            argument :tsquery, AshPostgres.Tsquery, allow_expr?: true, allow_nil?: false
          end
        end
      end

      if unquote(only) == [] or :full_text_search_rank in unquote(only) do
        calculations do
          calculate :full_text_search_rank,
                    :float,
                    expr(fragment("ts_rank(?, ?)", ^arg(:tsvector), ^arg(:tsquery))) do
            argument :tsvector, AshPostgres.Tsvector, allow_expr?: true, allow_nil?: false
            argument :tsquery, AshPostgres.Tsquery, allow_expr?: true, allow_nil?: false
          end
        end
      end

      if unquote(only) == [] or :tsquery in unquote(only) do
        calculations do
          calculate :tsquery,
                    AshPostgres.Tsquery,
                    expr(fragment("to_tsquery('simple', ?)", ^arg(:search))) do
            argument :search, :string, allow_expr?: true, allow_nil?: false
          end
        end
      end
    end
  end
end
