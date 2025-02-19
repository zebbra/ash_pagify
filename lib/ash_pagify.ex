defmodule AshPagify do
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  alias Ash.Page.Offset
  alias AshPagify.Error.Query.InvalidDirectionsError
  alias AshPagify.FilterForm
  alias AshPagify.Meta
  alias AshPagify.Misc
  alias AshPagify.Validation

  require Ash.Expr
  require Ash.Query
  require Logger

  @default_opts [
    default_limit: 25,
    max_limit: 100,
    scopes: %{},
    full_text_search: [],
    reset_on_filter?: true,
    replace_invalid_params?: false
  ]
  def default_opts, do: @default_opts
  @default_opts_keys Enum.map(@default_opts, fn {k, _} -> k end)
  def default_opts_keys, do: @default_opts_keys

  @internal_opts [
    :__compiled_scopes,
    :__compiled_default_scopes,
    :for,
    :full_text_search
  ]

  defstruct limit: nil,
            offset: nil,
            scopes: nil,
            filter_form: nil,
            filters: nil,
            order_by: nil,
            search: nil

  @typedoc """
  These options can be passed to most functions or configured via the
  application environment.

  ## Options

  Default ash_pagify options in addition to the ones provided by the
  `Ash.read/2` function. These options are used to configure the
  pagination behavior.

  - `:default_limit` - The default number of records to return. Defaults to 25.
    Can be overridden by the resource's `default_limit` function.
  - `:max_limit` - The maximum number of records that can be returned. Defaults
    to 100.
  - `:scopes` - A map of predefined filters to apply to the query. Each map
    entry itself is a group (list) of `t:AshPagify.scope/0` entries.
  - `:full_text_search` - A list of options for full-text search. See
    `t:AshPagify.Tsearch.tsearch_option/0`.
  - `:reset_on_filter?` - If set to `true`, the offset will be reset to 0 when
    a filter is applied. Defaults to `true`.
  - `:replace_invalid_params?` - If set to `true`, invalid parameters will be
    replaced with the default value. If set to `false`, invalid parameters
    will result in an error. Defaults to `false`.

  ## Look-up order

  Options are looked up in the following order:

  1. Function arguments (highest priority)
  2. Resource-level options (set in the resource module)
  3. Global options in the application environment (set in config files)
  4. Library defaults (lowest priority)

  """
  @type option ::
          {default_limit :: non_neg_integer()}
          | {max_limit :: non_neg_integer()}
          | {scopes :: map()}
          | {full_text_search :: list(AshPagify.Tsearch.tsearch_option())}
          | {reset_on_filter? :: boolean()}
          | {replace_invalid_params? :: boolean()}

  @typedoc """
  A scope is a predefined filter that is merged with the user-provided filters.

  Scope definitions live in the resource provided `ash_pagify_options scopes` function or in
  the provided `t:AshPagify.option/0`. Contrary to user-provided filters, scope filters
  are not parsed as user input and are not validated as such. However, they are
  validated in the `AshPagify.validate_and_run/4` context. User-provided parameters are
  used to lookup the scope filter. If the scope filter is found, it is applied to the query.
  If the scope filter is not found, an error is raised.

  ## Fields

  - `:name` - The name of the filter for the scope.
  - `:filter` - The filter to apply to the query.
  - `:default?` - If set to `true`, the scope is applied by default.
  """
  @type scope ::
          {name :: atom()}
          | {filter :: Ash.Filter.t()}
          | {default? :: boolean()}

  @typedoc """
  Valid order_by types for the `t:AshPagify.t/0` struct.
  """
  @type order_by :: [atom() | String.t() | {atom(), Ash.Sort.sort_order()} | [String.t()]] | nil

  @typedoc """
  Represents the query parameters for full-text search, scoping, filtering, ordering and pagination.

  ### Fields

  - `limit`, `offset`: Used for offset-based pagination.
  - `scopes`: A map of user provided scopes to apply to the query. Scopes are internally translated to
    predefined filters and merged into the query enginge.
  - `filter_form`: A map of filters provided by `AshPhoenix.FilterForm` module. These filters are meant
    to be used in user interfaces.
  - `filters`: A map of manually provided filters to apply to the query. These filters must be provided in
    the map syntax and are meant to be used in business logic context (see `Ash.Filter` for examples).
  - `order_by`: A list of fields to order by (see `Ash.Sort.parse_input/3` for all available orders).
  - `search`: A string to search for in the full-text search column.
  """
  @type t :: %__MODULE__{
          limit: pos_integer() | nil,
          offset: non_neg_integer() | nil,
          scopes: map() | nil,
          filter_form: map() | nil,
          filters: map() | nil,
          order_by: order_by(),
          search: String.t() | nil
        }

  @doc """
  Adds clauses for full-text search, scoping, filtering, ordering and pagination to an `t:Ash.Query.t/0`
  or `t:Ash.Resource.t/0` from the given `t:AshPagify.t/0` parameters and `t:Keyword.t/0` options.

  The keyword list `opts` is used to pass additional options to the query engine.
  It shoud conform to the list of valid options at `Ash.read/2`. Furthermore
  the `t:AshPagify.option/0` library options are supported.

  We take the keyword list `opts` and return a keyword list callback according to
  `Ash.read/2` but with the __:query__ keyword also within the list.

  - `AshPagify.search` is used to apply full-text search to the query.
  - `Paigfy.scopes` are used to apply predefined filters to the query.
  - `AshPagify.filter_form` is used to apply filters generated by the `AshPhoenix.FilterForm` module.
  - `AshPagify.filters` and `AshPagify.order_by` are used to filter and order the query.
  - `AshPagify.limit` and `AshPagify.offset` are used to paginate the query.

  The user input parameters are represented by the `t:AshPagify.t/0` type. Any `nil` values
  will be ignored.

  ## Examples

      iex> alias AshPagify.Factory.Post
      iex> ash_pagify = %AshPagify{limit: 10, offset: 20, filters: %{name: "foo"}, order_by: ["name"]}
      iex> [page, {:query, query}] = parse(Post, ash_pagify)
      iex> page
      {:page, [count: true, offset: 20, limit: 10]}
      iex> query
      #Ash.Query<resource: AshPagify.Factory.Post, filter: #Ash.Filter<name == "foo">, sort: [name: :asc]>

  Or to disable counting:

      iex> alias AshPagify.Factory.Post
      iex> ash_pagify = %AshPagify{limit: 10, offset: 20, filters: %{name: "foo"}, order_by: ["name"]}
      iex> [page, {:query, query}] = parse(Post, ash_pagify, page: [count: false])
      iex> page
      {:page, [count: false, offset: 20, limit: 10]}
      iex> query
      #Ash.Query<resource: AshPagify.Factory.Post, filter: #Ash.Filter<name == "foo">, sort: [name: :asc]>

  Sorting only:

      iex> alias AshPagify.Factory.Post
      iex> ash_pagify = %AshPagify{order_by: ["name"]}
      iex> [page, {:query, query}] = parse(Post, ash_pagify)
      iex> page
      {:page, [count: true, offset: 0, limit: 15]}
      iex> query
      #Ash.Query<resource: AshPagify.Factory.Post, sort: [name: :asc]>

  Filtering only:

      iex> alias AshPagify.Factory.Post
      iex> ash_pagify = %AshPagify{filters: %{name: "foo"}}
      iex> [page, {:query, query}] = parse(Post, ash_pagify)
      iex> page
      {:page, [count: true, offset: 0, limit: 15]}
      iex> query
      #Ash.Query<resource: AshPagify.Factory.Post, filter: #Ash.Filter<name == "foo">>

  Pagination only:

      iex> alias AshPagify.Factory.Post
      iex> ash_pagify = %AshPagify{limit: 10, offset: 20}
      iex> [page, {:query, query}] = parse(Post, ash_pagify)
      iex> page
      {:page, [count: true, offset: 20, limit: 10]}
      iex> query
      #Ash.Query<resource: AshPagify.Factory.Post>

  Scoping only:

      iex> alias AshPagify.Factory.Post
      iex> ash_pagify = %AshPagify{scopes: %{role: :admin}}
      iex> [page, {:query, query}] = parse(Post, ash_pagify)
      iex> page
      {:page, [count: true, offset: 0, limit: 15]}
      iex> query
      #Ash.Query<resource: AshPagify.Factory.Post, filter: #Ash.Filter<author == "John">>

  This function does _not_ validate or apply default parameters to the given
  AshPagify struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function. Doing so
  will automatically parse user provided input into the correct format for the
  query engine.
  """
  @spec parse(Ash.Query.t() | Ash.Resource.t(), AshPagify.t(), Keyword.t()) :: Keyword.t()
  def parse(query_or_resource, ash_pagify, opts \\ [])

  # sobelow_skip ["SQL.Query"]
  def parse(%Ash.Query{} = q, %AshPagify{} = ash_pagify, opts) do
    opts = Keyword.put(opts, :query, query(q, ash_pagify, opts))
    paginate(q, ash_pagify, opts)
  end

  def parse(r, %AshPagify{} = ash_pagify, opts) when is_atom(r) and r != nil do
    parse(Ash.Query.new(r), ash_pagify, opts)
  end

  @doc """
  Returns an `t:Ash.Page.Offset.t/0` struct from the given `t:Ash.Query.t/0` or `t:Ash.Resource.t/0`
  with the given `t:AshPagify.t/0` parameters and `t:Keyword.t/0` options.

  The `opts` keyword list is used to pass additional options to the query engine.
  It should conform to the list of valid options at `Ash.read/2`.

  - `AshPagify.search` is used to apply full-text search to the query.
  - `Paigfy.scopes` are used to apply predefined filters to the query.
  - `AshPagify.filter_form` is used to apply filters generated by the `AshPhoenix.FilterForm` module.
  - `AshPagify.filters` and `AshPagify.order_by` are used to filter and order the query.
  - `AshPagify.limit` and `AshPagify.offset` are used to paginate the query.

  The user input parameters are represented by the `t:AshPagify.t/0` type. Any `nil` values
  will be ignored.

  If the `:action` option is set (to perform a custom read action), the fourth argument
  `args` will be passed to the action as arguments.

  ## Examples

      iex> alias AshPagify.Factory.Post
      iex> %Ash.Page.Offset{results: r} =  AshPagify.all(Post, %AshPagify{filters: %{name: "inexistent"}})
      iex> r
      []

  Or with an initial query:

      iex> alias AshPagify.Factory.Post
      iex> q = Ash.Query.filter_input(Post, %{name: "inexistent"})
      iex> %Ash.Page.Offset{results: r} = AshPagify.all(q, %AshPagify{})
      iex> r
      []

  Or with a custom read action:
      iex> alias AshPagify.Factory.Post
      iex> alias AshPagify.Factory.Comment
      iex> Comment.read!() |> Enum.count()
      9
      iex> ash_pagify = %AshPagify{limit: 1, filters: %{name: "Post 1"}}
      iex> %Ash.Page.Offset{results: posts} = AshPagify.all(Post, ash_pagify)
      iex> post = hd(posts)
      iex> %Ash.Page.Offset{count: count} = AshPagify.all(Comment, %AshPagify{}, [action: :by_post], post.id)
      iex> count
      2

  Or with scopes:

      iex> alias AshPagify.Factory.Post
      iex> ash_pagify = %AshPagify{scopes: %{role: :admin}}
      iex> %Ash.Page.Offset{count: count} = AshPagify.all(Post, ash_pagify)
      iex> count
      1

  This function does _not_ validate or apply default parameters to the given
  AshPagify struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function. Doing so
  will automatically parse user provided input into the correct format for the
  query engine.
  """
  @spec all(Ash.Query.t() | Ash.Resource.t(), AshPagify.t(), Keyword.t(), any()) ::
          Offset.t()
  def all(query_or_resource, ash_pagify, opts \\ [], args \\ nil)

  def all(%Ash.Query{resource: r} = q, %AshPagify{} = ash_pagify, opts, args) do
    opts = parse(q, ash_pagify, opts)
    opts = remove_ash_pagify_opts(opts)

    case Keyword.get(opts, :action) do
      nil ->
        r.read!(opts)

      action ->
        {:ok, page} = apply(r, action, [args, opts])
        page
    end
  end

  def all(r, %AshPagify{} = ash_pagify, opts, args) when is_atom(r) and r != nil do
    all(Ash.Query.new(r), ash_pagify, opts, args)
  end

  defp remove_ash_pagify_opts(opts) do
    Enum.filter(opts, fn {k, _} ->
      !Enum.member?(@default_opts_keys, k) and !Enum.member?(@internal_opts, k)
    end)
  end

  @doc """
  Returns the total count of entries matching the full-text search, filters, filter_form,
  and scopes conditions in the given `t:Ash.Query.t/0` or `t:Ash.Resource.t/0` with the
  given `t:AshPagify.t/0` parameters and `t:Keyword.t/0` options.

  The pagination and ordering options are disregarded.

      iex> alias AshPagify.Factory.Post
      iex> AshPagify.count(Post, %AshPagify{})
      3

  You can override the default query by passing the `:count_query` option. This
  doesn't make a lot of sense when you use `count/3` directly, but allows you to
  optimize the count query when you use one of the `run/4`,
  `validate_and_run/4` and `validate_and_run!/4` functions.

      query = some expensive query
      count_query = Ash.Query.new(Post)
      AshPagify.count(Post, %AshPagify{}, count_query: count_query)

  The full-text search and various filter parameters of the given AshPagify are applied
  to the custom count query.

  If for some reason you already have the count, you can pass it as the `:count`
  option.

      count(query, %AshPagify{}, count: 42, for: Post)

  If you pass both the `:count` and the `:count_query` options, the `:count`
  option will take precedence.

  This function does _not_ validate or apply default parameters to the given
  AshPagify struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function. Doing so
  will automatically parse user provided input into the correct format for the
  query engine. Or you can use `AshPagify.validate_and_run/4` or
  `AshPagify.validate_and_run!/4` instead of this function.
  """
  @spec count(Ash.Query.t() | Ash.Resource.t(), AshPagify.t(), Keyword.t()) ::
          non_neg_integer()
  def count(query_or_resource, ash_pagify, opts \\ [])

  # sobelow_skip ["SQL.Query"]
  def count(%Ash.Query{resource: r} = q, %AshPagify{} = ash_pagify, opts) do
    if count = opts[:count] do
      count
    else
      q =
        if count_query = opts[:count_query] do
          count_query
        else
          query(q, ash_pagify, Keyword.put_new(opts, :for, r))
        end

      opts = Keyword.delete(opts, :count_query)
      opts = Keyword.delete(opts, :count)

      Ash.count!(q, opts)
    end
  end

  def count(r, %AshPagify{} = ash_pagify, opts) when is_atom(r) and r != nil do
    count(Ash.Query.new(r), ash_pagify, opts)
  end

  @doc """
  Applies the given `t:AshPagify.t/0` to the given `t:Ash.Query.t/0` or `t:Ash.Resource.t/0`,
  retrieves the data and the `t:AshPagify.Meta.t/0` data.

  This function does _not_ validate or apply default parameters to the given
  AshPagify struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function. Doing so
  will automatically parse user provided input into the correct format for the
  query engine. Or you can use `AshPagify.validate_and_run/4` or
  `AshPagify.validate_and_run!/4` instead of this function.

  ## Examples

      iex> alias AshPagify.Factory.Post
      iex> opts = [page: [count: false]]
      iex> ash_pagify = AshPagify.validate!(Post, %{filters: %{name: "inexistent"}}, opts)
      iex> {data, meta} = AshPagify.run(Post, ash_pagify, opts)
      iex> data == []
      true
      iex> match?(%AshPagify.Meta{}, meta)
      true

  See the documentation for `AshPagify.validate_and_run/4` for supported options.
  """
  @spec run(Ash.Query.t() | Ash.Resource.t(), AshPagify.t(), Keyword.t(), any()) ::
          {[Ash.Resource.record()], Meta.t()}
  def run(query_or_resource, ash_pagify, opts \\ [], args \\ nil)

  def run(%Ash.Query{} = q, %AshPagify{} = ash_pagify, opts, args) do
    page = all(q, ash_pagify, opts, args)
    meta = meta(page, ash_pagify, opts)
    {page.results, meta}
  end

  def run(r, %AshPagify{} = ash_pagify, opts, args) when is_atom(r) and r != nil do
    run(Ash.Query.new(r), ash_pagify, opts, args)
  end

  @doc """
  Validates the given ash_pagify parameters and retrieves the data and meta data on
  success.

  ## Examples

      iex> alias AshPagify.Factory.Post
      iex> {:ok, {[%Post{},%Post{},%Post{}], %AshPagify.Meta{}}} =
      ...>   AshPagify.validate_and_run(Post, %AshPagify{})
      iex> {:error, %AshPagify.Meta{} = meta} =
      ...>   AshPagify.validate_and_run(Post, %{limit: -1})
      iex> AshPagify.Error.clear_stacktrace(meta.errors)
      [
        limit: [
          %Ash.Error.Query.InvalidLimit{limit: -1}
        ]
      ]

  Or with a custom read action:

      iex> alias AshPagify.Factory.Post
      iex> alias AshPagify.Factory.Comment
      iex> Comment.read!() |> Enum.count()
      9
      iex> ash_pagify = %AshPagify{limit: 1, filters: %{name: "Post 1"}}
      iex> {:ok, {posts, _meta}} = AshPagify.validate_and_run(Post, ash_pagify)
      iex> post = hd(posts)
      iex> {:ok, {_comments, meta}} = AshPagify.validate_and_run(Comment, %AshPagify{}, [action: :by_post], post.id)
      iex> meta.total_count
      2

  Or with scopes:

      iex> alias AshPagify.Factory.Post
      iex> {:ok, {[%Post{}], %AshPagify.Meta{}}} = AshPagify.validate_and_run(Post, %AshPagify{scopes: %{role: :user}})

  ## Options

  The keyword list `opts` is used to pass additional options to the query engine.
  It shoud conform to the list of valid options at `Ash.read/2`. Furthermore
  the `t:AshPagify.option/0` library options are supported.
  """
  @spec validate_and_run(
          Ash.Query.t() | Ash.Resource.t(),
          map() | AshPagify.t(),
          Keyword.t(),
          any()
        ) ::
          {:ok, {[Ash.Resource.record()], Meta.t()}} | {:error, Meta.t()}
  def validate_and_run(query_or_resource, map_or_ash_pagify, opts \\ [], args \\ nil) do
    opts =
      query_or_resource
      |> Misc.maybe_put_compiled_scopes(opts)
      |> Keyword.put_new(:for, get_resource(query_or_resource))

    with {:ok, ash_pagify} <- validate(query_or_resource, map_or_ash_pagify, opts) do
      {:ok, run(query_or_resource, ash_pagify, opts, args)}
    end
  end

  @doc """
  Same as `AshPagify.validate_and_run/4`, but raises on error.
  """
  @spec validate_and_run!(
          Ash.Query.t() | Ash.Resource.t(),
          map() | AshPagify.t(),
          Keyword.t(),
          any()
        ) ::
          {[Ash.Resource.record()], Meta.t()}
  def validate_and_run!(query_or_resource, map_or_ash_pagify, opts \\ [], args \\ nil) do
    opts =
      query_or_resource
      |> Misc.maybe_put_compiled_scopes(opts)
      |> Keyword.put_new(:for, get_resource(query_or_resource))

    ash_pagify = validate!(query_or_resource, map_or_ash_pagify, opts)
    run(query_or_resource, ash_pagify, opts, args)
  end

  @doc """
  Returns meta information for the given query and ash_pagify that can be used for
  building the pagination links.

  ## Examples

      iex> alias AshPagify.Factory.Post
      iex> ash_pagify = %AshPagify{limit: 2, offset: 1, order_by: [name: :asc, comments_count: :desc_nils_last]}
      iex> page = AshPagify.all(Post, ash_pagify)
      iex> AshPagify.meta(page, ash_pagify)
      %AshPagify.Meta{
        current_limit: 2,
        current_offset: 1,
        current_page: 2,
        default_scopes: %{status: :all},
        has_next_page?: false,
        has_previous_page?: true,
        next_offset: nil,
        opts: [],
        ash_pagify: %AshPagify{filters: nil, limit: 2, offset: 1, order_by: [name: :asc, comments_count: :desc_nils_last]},
        previous_offset: 0,
        resource: Post,
        total_count: 3,
        total_pages: 2
      }

  This function does _not_ validate or apply default parameters to the given
  AshPagify struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function. Doing so
  will automatically parse user provided input into the correct format for the
  query engine.
  """
  @spec meta(Offset.t(), AshPagify.t(), Keyword.t()) :: Meta.t()
  def meta(%Offset{} = page, %AshPagify{} = ash_pagify, opts \\ []) do
    total_count = page.count
    page_size = page.limit
    total_pages = get_total_pages(total_count, page_size)
    current_offset = get_current_offset(page.offset)
    current_page = get_current_page(page, total_pages)
    current_search = ash_pagify.search

    {has_previous_page?, previous_offset} = get_previous(current_offset, page_size)
    {has_next_page?, next_offset} = get_next(current_offset, page_size, total_count)

    resource = get_resource(page)

    default_scopes = get_default_scopes(resource, opts)

    %Meta{
      current_limit: page_size,
      current_offset: current_offset,
      current_page: current_page,
      current_search: current_search,
      default_scopes: default_scopes,
      has_next_page?: has_next_page?,
      has_previous_page?: has_previous_page?,
      next_offset: next_offset,
      opts: remove_ash_pagify_opts(opts),
      ash_pagify: ash_pagify,
      previous_offset: previous_offset,
      resource: resource,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  defp get_resource(%Offset{rerun: {original_query, _}}), do: original_query.resource
  defp get_resource(%Ash.Query{resource: r}), do: r
  defp get_resource(resource) when is_atom(resource) and resource != nil, do: resource

  defp get_previous(offset, limit) do
    has_previous? = offset > 0
    previous_offset = if has_previous?, do: max(0, offset - limit), else: 0

    {has_previous?, previous_offset}
  end

  defp get_next(_, nil = _page_size, _) do
    {false, nil}
  end

  defp get_next(current_offset, page_size, total_count) when current_offset + page_size >= total_count do
    {false, nil}
  end

  defp get_next(current_offset, page_size, _) do
    {true, current_offset + page_size}
  end

  defp get_total_pages(0, _), do: 0
  defp get_total_pages(nil, _), do: 0
  defp get_total_pages(_, nil), do: 1
  defp get_total_pages(total_count, limit), do: ceil(total_count / limit)

  defp get_current_offset(nil), do: 0
  defp get_current_offset(offset), do: offset

  defp get_current_page(%Offset{offset: nil}, _), do: 1

  defp get_current_page(%Offset{offset: offset, limit: limit}, total_pages) do
    page = ceil(offset / limit) + 1
    min(page, total_pages)
  end

  defp get_default_scopes(resource, opts) do
    opts = Misc.maybe_put_compiled_scopes(resource, opts)
    Keyword.get(opts, :__compiled_default_scopes)
  end

  @doc """
  Transforms the given `order_by` parameter into a list of strings (user input domain).
  """
  @spec concat_sort(order_by(), [String.t()]) :: [String.t()]
  def concat_sort(list, acc \\ [])
  def concat_sort(nil, _), do: nil
  def concat_sort([], []), do: nil
  def concat_sort([], acc), do: Enum.reverse(acc)
  def concat_sort(order_by, acc) when is_binary(order_by), do: concat_sort([order_by], acc)
  def concat_sort(order_by, acc) when is_atom(order_by), do: concat_sort([order_by], acc)
  def concat_sort(order_by, acc) when is_tuple(order_by), do: concat_sort([order_by], acc)

  def concat_sort([field | rest], acc) do
    case field do
      {field, order} ->
        concat_sort(rest, ["#{order_to_prefix(order)}#{Atom.to_string(field)}" | acc])

      field when is_binary(field) ->
        concat_sort(rest, [field | acc])

      field when is_atom(field) ->
        concat_sort(rest, [Atom.to_string(field) | acc])
    end
  end

  defp order_to_prefix(:asc_nils_first), do: "++"
  defp order_to_prefix(:desc), do: "-"
  defp order_to_prefix(:desc_nils_last), do: "--"
  defp order_to_prefix(_), do: ""

  @doc """
  Transforms the given field with order prefix into an `t:Ash.Sort.sort_order/t`.

  ## Examples

      iex> AshPagify.prefix_to_order("name")
      :asc
      iex> AshPagify.prefix_to_order("-name")
      :desc
      iex> AshPagify.prefix_to_order("++name")
      :asc_nils_first
      iex> AshPagify.prefix_to_order("--name")
      :desc_nils_last
      iex> AshPagify.prefix_to_order("+name")
      :asc
  """
  @spec prefix_to_order(String.t()) :: Ash.Sort.sort_order()
  def prefix_to_order("++" <> field) when is_binary(field), do: :asc_nils_first
  def prefix_to_order("--" <> field) when is_binary(field), do: :desc_nils_last
  def prefix_to_order("+" <> field) when is_binary(field), do: :asc
  def prefix_to_order("-" <> field) when is_binary(field), do: :desc
  def prefix_to_order(_), do: :asc

  # Query

  @doc """
  Adds clauses for full-text search, scoping, filtering and ordering to an
  `t:Ash.Query.t/0` from the given `t:AshPagify.t/0` parameter.

  This function does _not_ validate or apply default parameters to the given
  AshPagify struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function. Doing so
  will automatically parse user provided input into the correct format for the
  query engine.

  ## Examples

      iex> alias AshPagify.Factory.Post
      iex> q = Ash.Query.new(Post)
      iex> ash_pagify = %AshPagify{filters: %{name: "John"}, order_by: ["name"]}
      iex> query(q, ash_pagify)
      #Ash.Query<resource: AshPagify.Factory.Post, filter: #Ash.Filter<name == "John">, sort: [name: :asc]>
  """
  @spec query(Ash.Query.t(), AshPagify.t(), Keyword.t()) :: Ash.Query.t()
  def query(%Ash.Query{} = q, %AshPagify{} = ash_pagify, opts \\ []) do
    q
    |> search(ash_pagify, opts)
    |> scope(ash_pagify, opts)
    |> filter_form(ash_pagify)
    |> filter(ash_pagify)
    |> order_by(ash_pagify)
  end

  ## Search

  @doc """
  Applies the `search` parameter of a `t:AshPagify.t/0` to an `t:Ash.Query.t/0`.

  Used by `AshPagify.query/2`. AshPagify allows you to perform full-text searches on resources. It uses the
  built-in [PostgreSQL full-text search functionality](https://www.postgresql.org/docs/current/textsearch.html).

  Have a look at the `t:AshPagify.Tsearch.tsearch_option/0` type for a list of available options.

  If search is provided and there is no order_by, the query will be sorted by the rank of the search.

  This function does _not_ validate or apply default parameters to the given
  AshPagify struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function. Doing so
  will automatically parse user provided input into the correct format for the
  query engine.
  """
  @spec search(Ash.Query.t(), AshPagify.t(), Keyword.t()) :: Ash.Query.t()
  def search(q, ash_pagify, opts \\ [])

  def search(%Ash.Query{} = q, %AshPagify{search: nil}, _opts), do: q
  def search(%Ash.Query{} = q, %AshPagify{search: ""}, _opts), do: q

  def search(%Ash.Query{} = q, %AshPagify{search: search} = ash_pagify, opts) do
    tsquery_str = AshPagify.Tsearch.tsquery(search, opts)
    tsquery_expr = Ash.Expr.expr(tsquery(search: ^tsquery_str))
    tsvector_expr = AshPagify.Tsearch.tsvector(opts)

    q
    |> Ash.Query.filter(full_text_search(tsvector: ^tsvector_expr, tsquery: ^tsquery_expr))
    |> maybe_put_ts_rank(ash_pagify, tsvector_expr, tsquery_expr)
  end

  defp maybe_put_ts_rank(%Ash.Query{} = q, %AshPagify{order_by: order_by}, tsvector_expr, tsquery_expr)
       when is_nil(order_by) or order_by == [] do
    Ash.Query.sort(q,
      full_text_search_rank: {%{tsvector: tsvector_expr, tsquery: tsquery_expr}, :desc}
    )
  end

  defp maybe_put_ts_rank(%Ash.Query{} = q, _, _, _), do: q

  ## Scope

  @doc """
  Applies the `scopes` parameter of a `t:AshPagify.t/0` to an `t:Ash.Query.t/0`.

  Used by `AshPagify.query/2`. At this stage we assume that the scopes are already
  compiled and validated. Further, default scopes are loaded into the AshPagify struct.

  For a completed list of filter operators, see `Ash.Filter`.

  This function does _not_ validate or apply default parameters to the given
  AshPagify struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function. Doing so
  will automatically parse user provided input into the correct format for the
  query engine.

  ## Examples

      iex> alias AshPagify.Factory.Post
      iex> q = Ash.Query.new(Post)
      iex> ash_pagify = %AshPagify{scopes: %{status: :active}}
      iex> scope(q, ash_pagify)
      #Ash.Query<resource: AshPagify.Factory.Post, filter: #Ash.Filter<age < \e[36m10\e[0m>>
  """
  @spec scope(Ash.Query.t(), AshPagify.t(), Keyword.t()) :: Ash.Query.t()
  def scope(q, ash_pagify, opts \\ [])

  def scope(%Ash.Query{} = q, %AshPagify{scopes: nil}, _), do: q

  def scope(%Ash.Query{resource: resource} = query, %AshPagify{scopes: scopes}, opts) when is_map(scopes) do
    opts = Misc.maybe_put_compiled_scopes(resource, opts)
    compiled_scopes = Keyword.get(opts, :__compiled_scopes)

    Enum.reduce(scopes, query, fn {group, name}, acc ->
      apply_scope(acc, compiled_scopes, group, name)
    end)
  end

  defp apply_scope(query, compiled_scopes, group, name) do
    group_scopes = get_group_scopes(compiled_scopes, group)
    scope = find_scope(group_scopes, group, name)

    if scope.filter == nil do
      query
    else
      Ash.Query.filter(query, ^scope.filter)
    end
  end

  defp get_group_scopes(compiled_scopes, group) do
    case Map.get(compiled_scopes, group) do
      nil -> raise ArgumentError, "Group `#{group}` not found"
      group_scopes -> group_scopes
    end
  end

  defp find_scope(group_scopes, group, name) do
    Enum.find(group_scopes, fn scope -> scope.name == name end) ||
      raise ArgumentError, "Scope `#{name}` not found in group `#{group}`"
  end

  ## Filter Form

  @doc """
  Applies the `filter_form` parameter of a `t:AshPagify.t/0` to an `t:Ash.Query.t/0`.

  Used by `AshPagify.query/2`. See `AshPhoenix.FilterForm` for more information.

  This function does _not_ validate or apply default parameters to the given
  AshPagify struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function. Doing so
  will automatically parse user provided input into the correct format for the
  query engine.

  ## Examples

      iex> alias AshPagify.Factory.Post
      iex> q = Ash.Query.new(Post)
      iex> ash_pagify = %AshPagify{filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"}}
      iex> filter_form(q, ash_pagify)
      #Ash.Query<resource: AshPagify.Factory.Post, filter: #Ash.Filter<name == "Post 1">>
  """
  @spec filter_form(Ash.Query.t(), AshPagify.t()) :: Ash.Query.t()
  def filter_form(q, ash_pagify)
  def filter_form(%Ash.Query{} = q, %AshPagify{filter_form: nil}), do: q

  def filter_form(%Ash.Query{} = q, %AshPagify{filter_form: %{} = filter_form}) when filter_form == %{}, do: q

  def filter_form(%Ash.Query{resource: r} = q, %AshPagify{filter_form: filter_form}) do
    filter_map = filter_form_to_filter_map(r, filter_form)
    Ash.Query.filter(q, ^filter_map)
  end

  def filter_form(%Ash.Query{} = q, _), do: q

  ## Filter

  @doc """
  Applies the `filter` parameter of a `t:AshPagify.t/0` to an `t:Ash.Query.t/0`.

  Used by `AshPagify.query/2`. See `Ash.Query.filter/2` for more information.

  For a completed list of filter operators, see `Ash.Filter`.

  This function does _not_ validate or apply default parameters to the given
  AshPagify struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function. Doing so
  will automatically parse user provided input into the correct format for the
  query engine.

  ## Examples

        iex> alias AshPagify.Factory.Post
        iex> q = Ash.Query.new(Post)
        iex> ash_pagify = %AshPagify{filters: %{name: "foo"}}
        iex> filter(q, ash_pagify)
        #Ash.Query<resource: AshPagify.Factory.Post, filter: #Ash.Filter<name == "foo">>

  Or multiple filters:

        iex> alias AshPagify.Factory.Post
        iex> q = Ash.Query.new(Post)
        iex> ash_pagify = %AshPagify{filters: %{name: "foo", id: "1"}}
        iex> filter(q, ash_pagify)
        #Ash.Query<resource: AshPagify.Factory.Post, filter: #Ash.Filter<id == "1" and name == "foo">>

  Or by relation:

        iex> alias AshPagify.Factory.Post
        iex> q = Ash.Query.new(Post)
        iex> ash_pagify = %AshPagify{filters: %{comments: %{body: "foo"}}}
        iex> filter(q, ash_pagify)
        #Ash.Query<resource: AshPagify.Factory.Post, filter: #Ash.Filter<comments.body == "foo">>
  """
  @spec filter(Ash.Query.t(), AshPagify.t()) :: Ash.Query.t()
  def filter(q, ash_pagify)

  def filter(%Ash.Query{} = q, %AshPagify{filters: nil}), do: q
  def filter(%Ash.Query{} = q, %AshPagify{filters: []}), do: q

  def filter(%Ash.Query{} = q, %AshPagify{filters: filters}) do
    Ash.Query.filter(q, ^filters)
  end

  def filter(%Ash.Query{} = q, _), do: q

  ## Ordering

  @doc """
  Applies the `order_by` parameter of a `t:AshPagify.t/0` to an `t:Ash.Query.t/0`.

  Used by `AshPagify.query/2`. See `Ash.Query.sort/3` for more information.

  This function does _not_ validate or apply default parameters to the given
  AshPagify struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function. Doing so
  will automatically parse user provided input into the correct format for the
  query engine.

  ## Examples
        iex> alias AshPagify.Factory.Post
        iex> q = Ash.Query.new(Post)
        iex> ash_pagify = %AshPagify{order_by: ["name"]}
        iex> order_by(q, ash_pagify)
        #Ash.Query<resource: AshPagify.Factory.Post, sort: [name: :asc]>

  Or descending order nulls last:
        iex> alias AshPagify.Factory.Post
        iex> q = Ash.Query.new(Post)
        iex> ash_pagify = %AshPagify{order_by: [name: :desc_nils_last]}
        iex> order_by(q, ash_pagify)
        #Ash.Query<resource: AshPagify.Factory.Post, sort: [name: :desc_nils_last]>

  Or multiple fields:
        iex> alias AshPagify.Factory.Post
        iex> q = Ash.Query.new(Post)
        iex> ash_pagify = %AshPagify{order_by: ["name", "id"]}
        iex> order_by(q, ash_pagify)
        #Ash.Query<resource: AshPagify.Factory.Post, sort: [name: :asc, id: :asc]>

  Or by calculation:
        iex> alias AshPagify.Factory.Post
        iex> q = Ash.Query.new(Post)
        iex> ash_pagify = %AshPagify{order_by: ["comments_count"]}
        iex> order_by(q, ash_pagify)
        #Ash.Query<resource: AshPagify.Factory.Post, sort: [comments_count: :asc]>
  """
  @spec order_by(Ash.Query.t(), AshPagify.t()) :: Ash.Query.t()
  def order_by(q, ash_pagify)

  def order_by(%Ash.Query{} = q, %AshPagify{order_by: nil}), do: q
  def order_by(%Ash.Query{} = q, %AshPagify{order_by: []}), do: q

  def order_by(%Ash.Query{} = q, %AshPagify{order_by: order_by}) do
    Ash.Query.sort(q, order_by)
  end

  def order_by(%Ash.Query{} = q, _), do: q

  # Pagination

  @doc """
  Adds clauses for pagination to the resulting keyword list from the given
  `t:AshPagify.t/0` parameter.

  The `count` parameter is set to `true` by default. To disable counting the
  total number of records, set `page: [:count, false]` in the opts keyword list.

  If the `limit` or `offset` fields are `nil`, the default limit and offset
  values will be used.

  If the resource itself provides a default limit, it will be used instead of
  the default limit provided by AshPagify.

  ## Examples

      iex> alias AshPagify.Factory.Post
      iex> ash_pagify = %AshPagify{limit: 10, offset: 20}
      iex> paginate(Post, ash_pagify)
      [page: [count: true, offset: 20, limit: 10]]

  Or disable counting:

      iex> alias AshPagify.Factory.Post
      iex> ash_pagify = %AshPagify{limit: 10, offset: 20}
      iex> paginate(Post, ash_pagify, page: [count: false])
      [page: [count: false, offset: 20, limit: 10]]

  Or without the offset parameter:

      iex> alias AshPagify.Factory.Post
      iex> ash_pagify = %AshPagify{limit: 8}
      iex> paginate(Post, ash_pagify)
      [page: [count: true, offset: 0, limit: 8]]

  Or without the limit parameter. The default limit from Post will be used:

      iex> alias AshPagify.Factory.Post
      iex> ash_pagify = %AshPagify{offset: 5}
      iex> paginate(Post, ash_pagify)
      [page: [count: true, offset: 5, limit: 15]]

  Or without the limit parameter. The default limit from AshPagify will be used if no
  default limit is provided by the resource:

      iex> alias AshPagify.Factory.Comment
      iex> ash_pagify = %AshPagify{offset: 5}
      iex> paginate(Comment, ash_pagify)
      [page: [count: true, offset: 5, limit: 25]]

  This function does _not_ validate or apply default parameters to the given
  AshPagify struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function. Doing so
  will automatically parse user provided input into the correct format for the
  query engine.
  """
  @spec paginate(Ash.Query.t() | Ash.Resource.t(), AshPagify.t(), Keyword.t()) :: Keyword.t()
  def paginate(query_or_resource, ash_pagify, opts \\ [])

  def paginate(%Ash.Query{} = q, %AshPagify{} = ash_pagify, opts) do
    page_opts = Keyword.get(opts, :page)

    page =
      q
      |> put_default_limit(ash_pagify)
      |> page(page_opts)

    Keyword.put(opts, :page, page)
  end

  def paginate(r, ash_pagify, opts) when is_atom(r) and r != nil do
    paginate(Ash.Query.new(r), ash_pagify, opts)
  end

  @spec put_default_limit(Ash.Query.t(), AshPagify.t()) :: AshPagify.t()
  defp put_default_limit(q, ash_pagify)

  defp put_default_limit(%Ash.Query{resource: r}, %AshPagify{limit: nil} = ash_pagify) when is_atom(r) and r != nil do
    %{ash_pagify | limit: Misc.get_option(:default_limit, for: r)}
  end

  defp put_default_limit(_, %AshPagify{limit: nil} = ash_pagify) do
    %{ash_pagify | limit: Misc.get_option(:default_limit)}
  end

  defp put_default_limit(_, ash_pagify), do: ash_pagify

  @doc """
  Returns a keyword list with the `limit`, `offset` and `count` parameters
  from the given `t:AshPagify.t/0` parameter.

  The `count` parameter is set to `true` by default. To disable counting the
  total number of records, set `count: false` in the optional page keyword list.

  ## Examples

      iex> ash_pagify = %AshPagify{limit: 10, offset: 20}
      iex> page(ash_pagify)
      [count: true, offset: 20, limit: 10]

  Or disable counting:

      iex> ash_pagify = %AshPagify{limit: 10, offset: 20}
      iex> page(ash_pagify, count: false)
      [count: false, offset: 20, limit: 10]
  """
  @spec page(AshPagify.t(), Keyword.t()) :: Keyword.t()
  def page(ash_pagify, page \\ [count: true])

  def page(%AshPagify{limit: limit, offset: offset}, count: count)
      when is_integer(limit) and limit >= 1 and (is_integer(offset) and offset >= 0) do
    []
    |> Keyword.put(:limit, limit)
    |> Keyword.put(:offset, offset)
    |> Keyword.put(:count, count)
  end

  def page(%AshPagify{limit: limit, offset: offset}, count: count)
      when is_integer(limit) and limit >= 1 and is_nil(offset) do
    []
    |> Keyword.put(:limit, limit)
    |> Keyword.put(:offset, 0)
    |> Keyword.put(:count, count)
  end

  def page(%AshPagify{limit: limit, offset: offset}, count: count)
      when is_nil(limit) and (is_integer(offset) and offset >= 0) do
    []
    |> Keyword.put(:limit, Misc.get_option(:default_limit))
    |> Keyword.put(:offset, offset)
    |> Keyword.put(:count, count)
  end

  def page(%AshPagify{limit: limit, offset: offset}, _)
      when is_integer(limit) and limit >= 1 and (is_integer(offset) and offset >= 0) do
    []
    |> Keyword.put(:limit, limit)
    |> Keyword.put(:offset, offset)
    |> Keyword.put(:count, true)
  end

  def page(%AshPagify{limit: limit, offset: offset}, _) when is_integer(limit) and limit >= 1 and is_nil(offset) do
    []
    |> Keyword.put(:limit, limit)
    |> Keyword.put(:offset, 0)
    |> Keyword.put(:count, true)
  end

  def page(%AshPagify{limit: limit, offset: offset}, _) when is_nil(limit) and (is_integer(offset) and offset >= 0) do
    []
    |> Keyword.put(:limit, Misc.get_option(:default_limit))
    |> Keyword.put(:offset, offset)
    |> Keyword.put(:count, true)
  end

  # Validation

  @doc """
  Validates a `t:AshPagify.t/0`.

  ## Examples

      iex> alias AshPagify.Factory.Post
      iex> params = %{limit: 10, offset: 20, other_param: "foo"}
      iex> AshPagify.validate(Post, params)
      {:ok, %AshPagify{limit: 10, offset: 20, scopes: %{status: :all}}}

      iex> ash_pagify = %AshPagify{offset: -1}
      iex> {:error, %AshPagify.Meta{} = meta} = AshPagify.validate(Post, ash_pagify)
      iex> AshPagify.Error.clear_stacktrace(meta.errors)
      [
        offset: [
          %Ash.Error.Query.InvalidOffset{offset: -1}
        ]
      ]

  The function is aware of the `Ash.Resource` type passed either as query or as
  resource. Thus the function is able to validate that only allowed fields are
  used for scoping, ordering and filtering. The function will also apply the
  default_limit and scoping if the resource provides one.
  """
  @spec validate(Ash.Query.t() | Ash.Resource.t(), map() | AshPagify.t(), Keyword.t()) ::
          {:ok, AshPagify.t()} | {:error, Meta.t()}
  def validate(query_or_resource, map_or_ash_pagify, opts \\ [])

  def validate(query_or_resource, %AshPagify{} = ash_pagify, opts) do
    map = ash_pagify_struct_to_map(ash_pagify)
    validate(query_or_resource, map, opts)
  end

  def validate(query_or_resource, %{} = params, opts) do
    result =
      Validation.validate_params(query_or_resource, params, opts)

    case result do
      {:ok, _} ->
        result

      {:error, errors, maybe_valid_params} ->
        Logger.debug("Invalid AshPagify: #{inspect(errors)}")
        {:error, Meta.with_errors(maybe_valid_params, errors, opts)}
    end
  end

  defp ash_pagify_struct_to_map(%AshPagify{} = ash_pagify) do
    ash_pagify
    |> Map.from_struct()
    |> Enum.reject(fn {_, value} -> is_nil(value) end)
    |> Map.new()
  end

  @doc """
  Same as `AshPagify.validate/2`, but raises a `AshPagify.Error.Query.InvalidParamsError` if the
  parameters are invalid.
  """
  @spec validate!(Ash.Query.t() | Ash.Resource.t(), map() | AshPagify.t(), Keyword.t()) ::
          AshPagify.t()
  def validate!(query_or_resource, map_or_ash_pagify, opts \\ []) do
    case validate(query_or_resource, map_or_ash_pagify, opts) do
      {:ok, ash_pagify} ->
        ash_pagify

      {:error, %Meta{errors: errors}} ->
        raise AshPagify.Error.Query.InvalidParamsError, errors: errors, params: map_or_ash_pagify
    end
  end

  @doc """
  Validates the given query or resource and ash_pagify parameters and returns a
  validated query.

  ## Examples

      iex> alias AshPagify.Factory.Post
      iex> ash_pagify = %AshPagify{limit: 10, offset: 20, order_by: ["name"], filters: %{name: "foo"}}
      iex> validated_query(Post, ash_pagify)
      #Ash.Query<resource: AshPagify.Factory.Post, filter: #Ash.Filter<name == "foo">, sort: [name: :asc]>
  """
  @spec validated_query(Ash.Query.t() | Ash.Resource.t(), map() | AshPagify.t(), Keyword.t()) ::
          Ash.Query.t()
  def validated_query(query_or_resource, map_or_ash_pagify, opts \\ [])

  # sobelow_skip ["SQL.Query"]
  def validated_query(%Ash.Query{} = q, map_or_ash_pagify, opts) do
    ash_pagify = validate!(q, map_or_ash_pagify, opts)
    query(q, ash_pagify, opts)
  end

  def validated_query(r, map_or_ash_pagify, opts) when is_atom(r) and r != nil do
    validated_query(Ash.Query.new(r), map_or_ash_pagify, opts)
  end

  @doc """
  Sets the tsvector value in the full_text_search clause of the `Keyword.t` opts parameter.

  If the full_text_search clause does not exist, it will be created. If the tsvector
  value already exists, it will be updated.

  ## Examples

      iex> set_tsvector("bar", [full_text_search: [tsvector: "foo"]])
      [full_text_search: [tsvector: "bar"]]

      iex> set_tsvector("bar")
      [full_text_search: [tsvector: "bar"]]

      iex> set_tsvector("foo", [full_text_search: [tsvector: "foo"]])
      [full_text_search: [tsvector: "foo"]]
  """
  def set_tsvector(tsvector, opts \\ []) do
    Keyword.update(
      opts,
      :full_text_search,
      [tsvector: tsvector],
      fn full_text_search ->
        Keyword.put(full_text_search, :tsvector, tsvector)
      end
    )
  end

  @doc """
  Sets the limit value of a `AshPagify` struct.

      iex> set_limit(%AshPagify{limit: 10, offset: 10}, 20)
      %AshPagify{limit: 20, offset: 10}

      iex> set_limit(%AshPagify{limit: 10, offset: 10}, "20")
      %AshPagify{limit: 20, offset: 10}

  The limit will not be allowed to go below 1.

      iex> set_limit(%AshPagify{}, -5)
      %AshPagify{limit: 25}

  If the limit is higher than the max_limit option, the limit will be set to the max_limit.

      iex> set_limit(%AshPagify{}, 102)
      %AshPagify{limit: 100}
  """
  @spec set_limit(AshPagify.t(), pos_integer(), Keyword.t()) :: AshPagify.t()
  def set_limit(ash_pagify, limit, opts \\ [])

  def set_limit(%AshPagify{} = ash_pagify, limit, opts) when is_integer(limit) and limit >= 1 do
    if limit <= Misc.get_option(:max_limit, opts) do
      %{ash_pagify | limit: limit}
    else
      %{ash_pagify | limit: Misc.get_option(:max_limit, opts)}
    end
  end

  def set_limit(%AshPagify{} = ash_pagify, limit, opts) when is_binary(limit) do
    set_limit(ash_pagify, String.to_integer(limit), opts)
  end

  def set_limit(%AshPagify{} = ash_pagify, _, opts) do
    %{ash_pagify | limit: Misc.get_option(:default_limit, opts)}
  end

  @doc """
  Sets the offset value of a `AshPagify` struct.

      iex> set_offset(%AshPagify{limit: 10, offset: 10}, 20)
      %AshPagify{offset: 20, limit: 10}

      iex> set_offset(%AshPagify{limit: 10, offset: 10}, "20")
      %AshPagify{offset: 20, limit: 10}

  The offset will not be allowed to go below 0.

      iex> set_offset(%AshPagify{}, -5)
      %AshPagify{offset: 0}
  """
  @spec set_offset(AshPagify.t(), non_neg_integer | binary) :: AshPagify.t()
  def set_offset(%AshPagify{} = ash_pagify, offset) when is_integer(offset) do
    %{
      ash_pagify
      | offset: max(offset, 0)
    }
  end

  def set_offset(%AshPagify{} = ash_pagify, offset) when is_binary(offset) do
    set_offset(ash_pagify, String.to_integer(offset))
  end

  @doc """
  Sets the offset of a AshPagify struct to the page depending on the limit.

  ## Examples

      iex> to_previous_offset(%AshPagify{offset: 20, limit: 10})
      %AshPagify{offset: 10, limit: 10}

      iex> to_previous_offset(%AshPagify{offset: 5, limit: 10})
      %AshPagify{offset: 0, limit: 10}

      iex> to_previous_offset(%AshPagify{offset: 0, limit: 10})
      %AshPagify{offset: 0, limit: 10}

      iex> to_previous_offset(%AshPagify{offset: -2, limit: 10})
      %AshPagify{offset: 0, limit: 10}
  """
  @spec to_previous_offset(AshPagify.t()) :: AshPagify.t()
  def to_previous_offset(%AshPagify{offset: 0} = ash_pagify), do: ash_pagify

  def to_previous_offset(%AshPagify{offset: offset, limit: limit} = ash_pagify)
      when is_integer(limit) and is_integer(offset),
      do: %{ash_pagify | offset: max(0, offset - limit)}

  @doc """
  Sets the offset of a AshPagify struct to the next page depending on the limit.

  If the total count is given as the second argument, the offset will not be
  increased if the last page has already been reached. You can get the total
  count from the `AshPagify.Meta` struct. If the AshPagify has an offset beyond the total
  count, the offset will be set to the last page.

  ## Examples

      iex> to_next_offset(%AshPagify{offset: 10, limit: 5})
      %AshPagify{offset: 15, limit: 5}

      iex> to_next_offset(%AshPagify{offset: 15, limit: 5}, 21)
      %AshPagify{offset: 20, limit: 5}

      iex> to_next_offset(%AshPagify{offset: 15, limit: 5}, 20)
      %AshPagify{offset: 15, limit: 5}

      iex> to_next_offset(%AshPagify{offset: 28, limit: 5}, 22)
      %AshPagify{offset: 20, limit: 5}

      iex> to_next_offset(%AshPagify{offset: -5, limit: 20})
      %AshPagify{offset: 0, limit: 20}
  """
  @spec to_next_offset(AshPagify.t(), non_neg_integer | nil) :: AshPagify.t()
  def to_next_offset(ash_pagify, total_count \\ nil)

  def to_next_offset(%AshPagify{limit: limit, offset: offset} = ash_pagify, _)
      when is_integer(limit) and is_integer(offset) and offset < 0,
      do: %{ash_pagify | offset: 0}

  def to_next_offset(%AshPagify{limit: limit, offset: offset} = ash_pagify, nil)
      when is_integer(limit) and is_integer(offset),
      do: %{ash_pagify | offset: offset + limit}

  def to_next_offset(%AshPagify{limit: limit, offset: offset} = ash_pagify, total_count)
      when is_integer(limit) and is_integer(offset) and is_integer(total_count) and offset >= total_count do
    %{ash_pagify | offset: (ceil(total_count / limit) - 1) * limit}
  end

  def to_next_offset(%AshPagify{limit: limit, offset: offset} = ash_pagify, total_count)
      when is_integer(limit) and is_integer(offset) and is_integer(total_count) do
    case offset + limit do
      new_offset when new_offset >= total_count -> ash_pagify
      new_offset -> %{ash_pagify | offset: new_offset}
    end
  end

  @doc """
  Sets the search of a AshPagify struct.

  If the reset option is set to false, the offset will not be reset to 0.

  ## Examples

      iex> set_search(%AshPagify{offset: 10}, "term")
      %AshPagify{search: "term"}

      iex> set_search(%AshPagify{offset: 10, search: "old"}, "new")
      %AshPagify{search: "new"}

      iex> set_search(%AshPagify{offset: 10, search: "old"}, nil)
      %AshPagify{search: nil}

  Or without reset offset:

      iex> set_search(%AshPagify{offset: 10}, "term", reset_on_filter?: false)
      %AshPagify{search: "term", offset: 10}
  """
  @spec set_search(AshPagify.t(), String.t() | nil, Keyword.t()) :: AshPagify.t()
  def set_search(ash_pagify, search, opts \\ [])

  def set_search(%AshPagify{} = ash_pagify, search, opts) do
    ash_pagify = %{ash_pagify | search: search}

    reset_on_filter = Misc.get_option(:reset_on_filter?, opts, true)

    if reset_on_filter do
      %{ash_pagify | offset: nil}
    else
      ash_pagify
    end
  end

  @doc """
  Sets the scope of a AshPagify struct.

  If the scope already exists, it will be replaced with the new value. If the
  scope does not exist, it will be added to the scopes map.

  If the reset option is set to false, the offset will not be reset to 0.

  ## Examples

      iex> set_scope(%AshPagify{offset: 10, scopes: %{status: :active}}, %{status: :inactive})
      %AshPagify{scopes: %{status: :inactive}}

      iex> set_scope(%AshPagify{offset: 10, scopes: %{status: :active}}, %{status: :active})
      %AshPagify{scopes: %{status: :active}}

  Or add a new scope:

      iex> set_scope(%AshPagify{offset: 10, scopes: %{role: :admin}}, %{status: :active})
      %AshPagify{scopes: %{status: :active, role: :admin}}

      iex> set_scope(%AshPagify{}, %{role: :admin})
      %AshPagify{scopes: %{role: :admin}}

  Or without reset offset:

      iex> set_scope(%AshPagify{offset: 10}, %{status: :active}, reset_on_filter?: false)
      %AshPagify{scopes: %{status: :active}, offset: 10}
  """
  @spec set_scope(AshPagify.t(), map(), Keyword.t()) :: AshPagify.t()
  def set_scope(ash_pagify, scope, opts \\ [])

  def set_scope(%AshPagify{} = ash_pagify, scope, opts) do
    scopes = ash_pagify.scopes || %{}
    ash_pagify = %{ash_pagify | scopes: Map.merge(scopes, scope)}

    reset_on_filter = Misc.get_option(:reset_on_filter?, opts, true)

    if reset_on_filter do
      %{ash_pagify | offset: nil}
    else
      ash_pagify
    end
  end

  @doc """
  Helper function to check if a scope is active in a AshPagify struct.

  ## Examples

      iex> active_scope?(%AshPagify{scopes: %{status: :active}}, %{status: :active})
      true

      iex> active_scope?(%AshPagify{scopes: %{status: :active}}, %{status: :inactive})
      false

      iex> active_scope?(%AshPagify{scopes: %{status: :active}}, %{role: :admin})
      false

      iex> active_scope?(%AshPagify{}, %{role: :admin})
      false
  """
  @spec active_scope?(AshPagify.t(), map()) :: boolean
  def active_scope?(%AshPagify{scopes: nil}, _), do: false

  def active_scope?(%AshPagify{scopes: scopes}, scope) do
    group = scope |> Map.keys() |> hd()
    name = scope |> Map.values() |> hd()

    case Map.get(scopes, group) do
      nil -> false
      active -> active == name
    end
  end

  @doc """
  Removes all filters from a AshPagify struct.

  ## Example

      iex> reset_filters(%AshPagify{filters: %{
      ...>  name: "foo",
      ...> }})
      %AshPagify{filters: %{}}
  """
  @spec reset_filters(AshPagify.t()) :: AshPagify.t()
  def reset_filters(%AshPagify{} = ash_pagify), do: %{ash_pagify | filters: %{}}

  @doc """
  Removes all filter_form from a AshPagify struct.

  ## Example

      iex> reset_filter_form(%AshPagify{
      ...>   filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"}
      ...> })

      %AshPagify{filter_form: %{}}
  """
  @spec reset_filter_form(AshPagify.t()) :: AshPagify.t()
  def reset_filter_form(%AshPagify{} = ash_pagify), do: %{ash_pagify | filter_form: %{}}

  @doc """
  Updates the filter form of a AshPagify struct.

  If the filter already exists, it will be replaced with the new value. If the
  filter does not exist, it will be added to the filter form map.

  If the reset option is set to false, the offset will not be reset to 0.

  ## Examples
      iex>  set_filter_form(%AshPagify{}, %{"field" => "name", "operator" => "eq", "value" => "Post 2"})
      %AshPagify{filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 2"}}

      iex> set_filter_form(%AshPagify{filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"}}, %{"field" => "name", "operator" => "eq", "value" => "Post 2"})
      %AshPagify{filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 2"}}

      iex> set_filter_form(%AshPagify{filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"}}, %{"negated" => false, "operator" => "and"})
      %AshPagify{filter_form: nil}
  """
  @spec set_filter_form(AshPagify.t(), map(), Keyword.t()) :: AshPagify.t()
  def set_filter_form(ash_pagify, filter_form, opts \\ [])

  def set_filter_form(%AshPagify{} = ash_pagify, filter_form, opts)
      when filter_form == %{"negated" => false, "operator" => "and"} do
    maybe_reset_offset(%{ash_pagify | filter_form: nil}, opts)
  end

  def set_filter_form(%AshPagify{} = ash_pagify, filter_form, opts) do
    maybe_reset_offset(%{ash_pagify | filter_form: filter_form}, opts)
  end

  defp maybe_reset_offset(%AshPagify{} = ash_pagify, opts) do
    reset_on_filter = Misc.get_option(:reset_on_filter?, opts, true)

    if reset_on_filter do
      %{ash_pagify | offset: nil}
    else
      ash_pagify
    end
  end

  @doc """
  Merges the given filters with the filters of a AshPagify struct.

  If the filter already exists, it will be replaced with the new value. If the
  filter does not exist, it will be added to the filters map.

  In order to merge the filters, the filters are first prepared by calling `prepare_filters/1`.
  This function will ensure that the filters are in the correct format for merging
  (e.g. keys are strings).

  If the filters are in the correct format, the filters are merged using `Misc.deep_merge/2`.
  After merging, the filters are cleaned up by removing empty lists.

  ## Examples

      iex> merge_filters(%AshPagify{filters: %{name: "foo"}}, %{name: "bar"})
      %AshPagify{filters: %{"and" => [%{"name" => "bar"}]}}

      iex> merge_filters(%AshPagify{filters: %{name: "foo"}}, %{age: 10})
      %AshPagify{filters: %{"and" => [%{"name" => "foo"}, %{"age" => 10}]}}

      iex> merge_filters(%AshPagify{filters: %{"or" => [%{name: "foo"}]}}, %{age: 10})
      %AshPagify{filters: %{"or" => [%{"name" => "foo"}], "and" => [%{"age" => 10}]}}

      iex> merge_filters(%AshPagify{filters: %{"or" => [%{name: "foo"}]}}, %{"or" => [%{age: 10}]})
      %AshPagify{filters: %{"or" => [%{"name" => "foo"}, %{"age" => 10}]}}
  """
  @spec merge_filters(AshPagify.t(), map() | true) :: AshPagify.t()
  def merge_filters(ash_pagify, nil), do: ash_pagify
  def merge_filters(ash_pagify, true), do: ash_pagify

  def merge_filters(%AshPagify{} = ash_pagify, filters) do
    source = prepare_filters(ash_pagify.filters || %{})
    target = prepare_filters(filters || %{})

    merged =
      source
      |> Misc.deep_merge(target)
      |> Enum.reject(fn {_, value} -> value == [] end)
      |> Map.new()

    %{ash_pagify | filters: merged}
  end

  defp prepare_filters(%{} = filters) do
    keys = Map.keys(filters)

    cond do
      keys == [] ->
        %{"and" => []}

      Enum.member?(keys, "and") or Enum.member?(keys, "or") ->
        Misc.stringify_keys(filters)

      true ->
        %{"and" => [Misc.stringify_keys(filters)]}
    end
  end

  defp prepare_filters(filters), do: Misc.stringify_keys(filters)

  @doc """
  Transforms the `filter_form` parameter of a `t:AshPagify.t/0` into a filter map.

  Used by `AshPagify.filter_form/2`. See `AshPhoenix.FilterForm` for more information.

  This function does _not_ validate or apply default parameters to the given
  AshPagify struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function. Doing so
  will automatically parse user provided input into the correct format for the
  query engine.

  ## Examples

      iex> alias AshPagify.Factory.Post
      iex> ash_pagify = %AshPagify{filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"}}
      iex> filter_form_to_filter_map(Post, ash_pagify.filter_form)
      %{"and" => [%{"name" => %{"eq" => "Post 1"}}]}
  """
  @spec filter_form_to_filter_map(Ash.Resource.t(), map() | nil) :: map()
  def filter_form_to_filter_map(_resource, nil), do: %{}

  def filter_form_to_filter_map(resource, filter_form) do
    resource
    |> FilterForm.new(params: filter_form)
    |> FilterForm.to_filter_map()
    |> elem(1)
  end

  @doc """
  Takes the AshPagify.scopes and AshPagify.form_filter and compiles them into a
  map of filters. The filters are merged with the base filters of the AshPagify struct.

  At this stage we assume that the filters, filter_form, and scopes have been validated
  and are valid.

  > #### Full-text search {: .info}
  > Per default we do store the full-text search term along with the user
  provided full-text search options  in the compiled filters map. If
  you do not need to include the full-text search setting in the compiled filters
  map, you can set the `include_full_text_search?` option to `false`.
  The full-text search setting is stored under the key `"__full_text_search"` in the
  resulting filters map. This can be handy if you want to store the current filter
  state including the full-text search setting and retrieve it later. See
  `AshPagify.query_for_filters_map/2` for an example.

  Precedence:
  - scopes (will overwrite filter_form and filters)
  - filter_form (will overwrite filters)
  - filters

  ## Examples

      iex> alias AshPagify.Factory.Post
      iex> query_to_filters_map(Post, %AshPagify{scopes: [{:role, :admin}]})
      %AshPagify{filters: %{"and" => [%{"author" => "John"}]}, scopes: [role: :admin]}

      iex> query_to_filters_map(Post, %AshPagify{filters: %{name: "foo"}})
      %AshPagify{filters: %{"and" => [%{"name" => "foo"}]}}

      iex> query_to_filters_map(
      ...>   Post,
      ...>   %AshPagify{
      ...>     filters: %{author: "Author 1"},
      ...>     filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"},
      ...>     scopes: [{:role, :admin}]
      ...>   }
      ...> )
      %AshPagify{
        scopes: [role: :admin],
        filters: %{"and" => [%{"author" => "John"}, %{"name" => %{"eq" => "Post 1"}}]},
        filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"}
      }

      # Or with a full-text search term

      iex> query_to_filters_map(
      ...>   Post,
      ...>   %AshPagify{
      ...>     search: "search term",
      ...>     filters: %{author: "Author 1"},
      ...>     filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"},
      ...>     scopes: [{:role, :admin}]
      ...>   }
      ...> )
      %AshPagify{
        scopes: [role: :admin],
        filters: %{
          "and" => [
            %{"author" => "John"},
            %{"name" => %{"eq" => "Post 1"}}
          ],
          "__full_text_search" => %{
            "search" => "search term"
          }
        },
        filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"},
        search: "search term"
      }
  """
  @spec query_to_filters_map(Ash.Query.t() | Ash.Resource.t(), AshPagify.t(), Keyword.t()) ::
          AshPagify.t()
  def query_to_filters_map(query_or_resource, ash_pagify, opts \\ [])

  def query_to_filters_map(%Ash.Query{resource: resource}, %AshPagify{} = ash_pagify, opts) do
    filter_form = filter_form_to_filter_map(resource, ash_pagify.filter_form)
    scopes_filters = load_scopes_filters(resource, ash_pagify.scopes, opts)

    ash_pagify
    |> merge_filters(filter_form)
    |> merge_filters(scopes_filters)
    |> maybe_store_full_text_search(resource, opts)
  end

  def query_to_filters_map(r, %AshPagify{} = ash_pagify, opts) when is_atom(r) and r != nil do
    query_to_filters_map(Ash.Query.new(r), ash_pagify, opts)
  end

  defp load_scopes_filters(_resource, nil, _opts), do: %{}

  defp load_scopes_filters(resource, scopes, opts) do
    opts = Misc.maybe_put_compiled_scopes(resource, opts)
    compiled_scopes = Keyword.get(opts, :__compiled_scopes)

    Enum.reduce(scopes, %{}, fn {group, name}, acc ->
      get_scope_filter(acc, compiled_scopes, group, name)
    end)
  end

  defp get_scope_filter(filters, compiled_scopes, group, name) do
    group_scopes = get_group_scopes(compiled_scopes, group)
    scope = find_scope(group_scopes, group, name)

    if scope.filter == nil do
      filters
    else
      Map.merge(filters, scope.filter)
    end
  end

  defp maybe_store_full_text_search(%AshPagify{search: nil} = ash_pagify, _resource, _opts), do: ash_pagify

  defp maybe_store_full_text_search(%AshPagify{search: ""} = ash_pagify, _resource, _opts), do: ash_pagify

  defp maybe_store_full_text_search(%AshPagify{search: search} = ash_pagify, resource, opts) do
    if search != nil and Keyword.get(opts, :include_full_text_search?, true) do
      store_full_text_search(ash_pagify, resource, opts)
    else
      ash_pagify
    end
  end

  defp store_full_text_search(%AshPagify{search: search} = ash_pagify, resource, opts) do
    ash_pagify
    |> Validation.validate_search(Keyword.put_new(opts, :for, resource))
    |> maybe_raise_on_invalid_search(search, opts)
  end

  defp maybe_raise_on_invalid_search(ash_pagify, search, opts) do
    if Map.get(ash_pagify, :errors) == nil do
      user_provided_full_text_search_opts =
        opts
        |> Keyword.get(:full_text_search, [])
        |> Keyword.put(:search, search)
        |> maybe_put_tsvector(get_in(opts, [:full_text_search, :tsvector]))
        |> Enum.filter(fn {key, _} -> key in AshPagify.Tsearch.option_keys() end)
        |> Map.new()
        |> Misc.stringify_keys(keys: AshPagify.Tsearch.option_keys(), depth: 1)

      %{
        ash_pagify
        | filters:
            Map.put(
              ash_pagify.filters || %{},
              "__full_text_search",
              user_provided_full_text_search_opts
            )
      }
    else
      if Keyword.get(opts, :raise_on_invalid_search?, true) do
        ash_pagify
        |> Map.get(:errors, [])
        |> Keyword.get(:search, [])
        |> hd()
        |> raise()
      else
        ash_pagify
      end
    end
  end

  defp maybe_put_tsvector(opts, nil), do: opts

  defp maybe_put_tsvector(opts, tsvector) when is_binary(tsvector), do: Keyword.put(opts, :tsvector, tsvector)

  defp maybe_put_tsvector(opts, tsvector) when is_atom(tsvector),
    do: Keyword.put(opts, :tsvector, Atom.to_string(tsvector))

  defp maybe_put_tsvector(opts, _), do: opts

  @doc """
  Creates an `Ash.Query` from a filter map. Ideally, the filter map was previously
  compiled with `AshPagify.query_to_filters_map/2`.

  Optionally, you can pass the `include_full_text_search?: false` option to disable
  the full-text search term inclusion in the query.

  If the full-text search term is included in the compiled filters map, it will be
  removed from the filters map before the query is created. Further, the full-text
  search is validated before beeing applied to the query. If the full-text search
  is invalid and the `raise_on_invalid_search?` option is not set to `false`, the
  function will raise an error.

  ## Examples

      iex> alias AshPagify.Factory.Post
      iex> filters_map = %{"and" => [%{"name" => "foo"}]}
      iex> query_for_filters_map(Post, filters_map)
      #Ash.Query<resource: AshPagify.Factory.Post, filter: #Ash.Filter<name == "foo">>
  """
  @spec query_for_filters_map(Ash.Query.t() | Ash.Resource.t(), map(), Keyword.t()) ::
          Ash.Query.t()
  def query_for_filters_map(query_or_resource, filters_map, opts \\ [])

  def query_for_filters_map(query_or_resource, %{} = filters_map, opts) do
    {filters_map, full_text_search} = extract_full_text_search(filters_map)

    query_or_resource
    |> Ash.Query.filter_input(filters_map)
    |> maybe_apply_full_text_search(full_text_search, opts)
  end

  @doc """
  Extracts the full-text search setting from the filters map and returns a tuple of the filters map
  without the full-text search setting and the full-text search setting.

  The full-text search setting is stored under the key `"__full_text_search"` in the
  filters map (on in the `and` or `or` base of the filters_map). If the full-text
  search setting is not found, the function will return the filters map as is.
  """
  @spec extract_full_text_search(map()) :: {map(), map() | nil}
  def extract_full_text_search(%{"__full_text_search" => full_text_search} = filters_map) do
    {Map.delete(filters_map, "__full_text_search"), full_text_search}
  end

  def extract_full_text_search(%{"and" => filters} = filters_map) do
    split_and_combine(filters_map, filters, "and")
  end

  def extract_full_text_search(%{"or" => filters} = filters_map) do
    split_and_combine(filters_map, filters, "or")
  end

  def extract_full_text_search(filters_map), do: {filters_map, nil}

  defp split_and_combine(filters_map, combinator_filters, combinator) do
    {full_text_search, combinator_filters} =
      Enum.split_with(combinator_filters, &Map.has_key?(&1, "__full_text_search"))

    filters_map =
      cond do
        combinator_filters == [] && full_text_search == [] -> filters_map
        combinator_filters == [] -> Map.delete(filters_map, combinator)
        true -> Map.put(filters_map, combinator, combinator_filters)
      end

    full_text_search =
      if full_text_search == [] do
        nil
      else
        full_text_search
        |> hd()
        |> Map.get("__full_text_search", nil)
      end

    {filters_map, full_text_search}
  end

  @spec maybe_apply_full_text_search(Ash.Query.t(), map(), Keyword.t()) :: Ash.Query.t()
  defp maybe_apply_full_text_search(%Ash.Query{} = query, nil, _opts), do: query
  defp maybe_apply_full_text_search(query, %{"search" => nil}, _opts), do: query
  defp maybe_apply_full_text_search(query, %{"search" => ""}, _opts), do: query

  defp maybe_apply_full_text_search(%Ash.Query{} = query, full_text_search, opts) do
    if Keyword.get(opts, :include_full_text_search?, true) do
      apply_full_text_search(query, full_text_search, opts)
    else
      query
    end
  end

  @spec apply_full_text_search(Ash.Query.t(), map(), Keyword.t()) :: Ash.Query.t()
  defp apply_full_text_search(%Ash.Query{resource: r} = query, %{"search" => search} = full_text_search, opts) do
    ash_pagify = %AshPagify{search: search}

    full_text_search =
      full_text_search
      |> Map.delete("search")
      |> Enum.map(fn {key, value} -> {String.to_existing_atom(key), value} end)
      |> Enum.filter(fn {key, _} -> key in AshPagify.Tsearch.option_keys() end)

    opts =
      opts
      |> Keyword.put(:full_text_search, full_text_search)
      |> Keyword.put_new(:for, r)

    ash_pagify
    |> Validation.validate_search(opts)
    |> maybe_raise_on_invalid_search_apply(query, opts)
  end

  defp maybe_raise_on_invalid_search_apply(ash_pagify, query, opts) do
    if Map.get(ash_pagify, :errors) == nil do
      search(query, ash_pagify, opts)
    else
      if Keyword.get(opts, :raise_on_invalid_search?, true) do
        ash_pagify
        |> Map.get(:errors, [])
        |> Keyword.get(:search, [])
        |> hd()
        |> raise()
      else
        query
      end
    end
  end

  @doc """
  Returns the current order direction for the given field.

  ## Examples

      iex> ash_pagify = %AshPagify{order_by: [name: :desc, age: :asc]}
      iex> current_order(ash_pagify, :name)
      :desc
      iex> current_order(ash_pagify, :age)
      :asc
      iex> current_order(ash_pagify, :species)
      nil

  If the field is not an atom, the function will return `nil`.

      iex> ash_pagify = %AshPagify{order_by: [name: :desc]}
      iex> current_order(ash_pagify, "name")
      nil

  If `AshPagify.order_by` is nil, the function will return `nil`.

      iex> current_order(%AshPagify{}, :name)
      nil
  """
  @spec current_order(AshPagify.t(), atom) :: Ash.Sort.sort_order() | nil
  def current_order(%AshPagify{order_by: nil}, _field), do: nil

  def current_order(%AshPagify{order_by: order_by}, field) when is_atom(field) do
    case Enum.find(order_by, &(elem(&1, 0) == field)) do
      {_, order} -> order
      nil -> nil
    end
  end

  def current_order(_, _), do: nil

  @doc """
  Resets the order of a AshPagify struct.

  ## Example

      iex> reset_order(%AshPagify{order_by: [name: :asc]})
      %AshPagify{order_by: nil}

  """
  @spec reset_order(AshPagify.t()) :: AshPagify.t()
  def reset_order(%AshPagify{} = ash_pagify), do: %{ash_pagify | order_by: nil}

  @doc """
  Updates the `order_by` value of a `AshPagify` struct.

  - If the field is not in the current `order_by` value, it will be prepended to
    the list. By default, the order direction for the field will be set to
    `:asc`.
  - If the field is already at the front of the `order_by` list, the order
    direction will be reversed.
  - If the field is already in the list, but not at the front, it will be moved
    to the front and the order direction will be set to `:asc` (or the custom
    asc direction supplied in the `:directions` option).
  - If the `:directions` option --a 2-element tuple-- is passed, the first and
    second elements will be used as custom sort declarations for ascending and
    descending, respectively.

  ## Examples

      iex> ash_pagify = push_order(%AshPagify{}, :name)
      iex> ash_pagify.order_by
      [name: :asc]
      iex> ash_pagify = push_order(ash_pagify, :age)
      iex> ash_pagify.order_by
      [age: :asc, name: :asc]
      iex> ash_pagify = push_order(ash_pagify, :age)
      iex> ash_pagify.order_by
      [age: :desc, name: :asc]
      iex> ash_pagify = push_order(ash_pagify, :species)
      iex> ash_pagify.order_by
      [species: :asc, age: :desc, name: :asc]
      iex> ash_pagify = push_order(ash_pagify, :age)
      iex> ash_pagify.order_by
      [age: :asc, species: :asc, name: :asc]

  By default, the function toggles between `:asc` and `:desc`. You can override
  this with the `:directions` option.

      iex> directions = {:asc_nils_first, :desc_nils_last}
      iex> ash_pagify = push_order(%AshPagify{}, :ttfb, directions: directions)
      iex> ash_pagify.order_by
      [ttfb: :asc_nils_first]
      iex> ash_pagify = push_order(ash_pagify, :ttfb, directions: directions)
      iex> ash_pagify.order_by
      [ttfb: :desc_nils_last]

  This also allows you to sort in descending order initially.

      iex> directions = {:desc, :asc}
      iex> ash_pagify = push_order(%AshPagify{}, :ttfb, directions: directions)
      iex> ash_pagify.order_by
      [ttfb: :desc]
      iex> ash_pagify = push_order(ash_pagify, :ttfb, directions: directions)
      iex> ash_pagify.order_by
      [ttfb: :asc]

  If a string is passed as the second argument, it will be converted to an atom
  using `String.to_existing_atom/1`. If the atom does not exist, the `AshPagify`
  struct will be returned unchanged.

      iex> ash_pagify = push_order(%AshPagify{}, "name")
      iex> ash_pagify.order_by
      [name: :asc]
      iex> ash_pagify = push_order(%AshPagify{}, "this_atom_does_not_exist")
      iex> ash_pagify.order_by
      nil

  If the `order_by` is either an atom or a binary, the function will return the coerced `order_by` value.

      iex> ash_pagify = push_order(%AshPagify{order_by: "author"}, :name)
      iex> ash_pagify.order_by
      [name: :asc, author: :asc]
      iex> ash_pagify = push_order(%AshPagify{order_by: :author}, "name")
      iex> ash_pagify.order_by
      [name: :asc, author: :asc]

  If the `:limit_order_by` option is passed, the `order_by` will be limited to the given number of fields.

      iex> ash_pagify = push_order(%AshPagify{order_by: [name: :asc, age: :asc]}, :species, limit_order_by: 1)
      iex> ash_pagify.order_by
      [species: :asc]
  """
  @spec push_order(AshPagify.t(), atom() | String.t(), Keyword.t()) :: AshPagify.t()
  def push_order(ash_pagify, field, opts \\ [])

  def push_order(%AshPagify{order_by: order_by} = ash_pagify, field, opts) when is_atom(field) do
    order_by = coerce_order_by(order_by)
    previous_index = get_index(order_by, field)
    previous_direction = get_order_direction(order_by, previous_index)

    directions = Keyword.get(opts, :directions, nil)
    new_direction = new_order_direction(previous_index, previous_direction, directions)

    order_by =
      case previous_index do
        nil ->
          [{field, new_direction} | order_by]

        idx ->
          [{field, new_direction} | List.delete_at(order_by, idx)]
      end

    order_by = limit_order_by(order_by, opts)

    %AshPagify{ash_pagify | order_by: order_by}
  end

  def push_order(ash_pagify, field, opts) when is_binary(field) do
    push_order(ash_pagify, String.to_existing_atom(field), opts)
  rescue
    ArgumentError -> ash_pagify
  end

  defp limit_order_by(order_by, opts) do
    case Keyword.get(opts, :limit_order_by) do
      limit when is_integer(limit) and limit > 0 -> Enum.take(order_by, limit)
      _ -> order_by
    end
  end

  @doc """
  Transforms the given `order_by` parameter into a list of tuples with
  the field and the default :asc direction.

  ## Examples

      iex> coerce_order_by(nil)
      []
      iex> coerce_order_by([])
      []
      iex> coerce_order_by(:name)
      [name: :asc]
      iex> coerce_order_by("name")
      [name: :asc]
      iex> coerce_order_by({:name, :asc})
      [name: :asc]
      iex> coerce_order_by([name: :asc, age: :desc])
      [name: :asc, age: :desc]
  """
  @spec coerce_order_by(order_by()) :: order_by()
  def coerce_order_by(nil), do: []
  def coerce_order_by([]), do: []
  def coerce_order_by(order_by) when is_atom(order_by), do: [{order_by, :asc}]

  def coerce_order_by(order_by) when is_binary(order_by), do: [{String.to_existing_atom(order_by), :asc}]

  def coerce_order_by(order_by) when is_tuple(order_by), do: [order_by]

  def coerce_order_by(order_by) when is_list(order_by) do
    Enum.map(order_by, fn
      {field, direction} when is_binary(field) -> {String.to_existing_atom(field), direction}
      {field, direction} -> {field, direction}
      field when is_binary(field) -> {String.to_existing_atom(field), :asc}
      field when is_atom(field) -> {field, :asc}
    end)
  end

  @doc """
  Finds the current index of a field in the `order_by` list.

  Following rules are applied:

  - if the `order_by` is `nil`, `nil` is returned
  - if the `order_by` is an atom or a binary, `nil` is returned
  - if the `order_by` is a tuple, `nil` is returned
  - if the `order_by` is a list, the index of the field is returned
  """
  @spec get_index(order_by(), atom()) :: non_neg_integer() | nil
  def get_index(order_by, field)
  def get_index(nil, _field), do: nil
  def get_index([], _field), do: nil
  def get_index(order_by, _field) when is_atom(order_by), do: nil
  def get_index(order_by, _field) when is_binary(order_by), do: nil
  def get_index(order_by, _field) when is_tuple(order_by), do: nil

  def get_index(order_by, field) when is_binary(field), do: get_index(order_by, String.to_existing_atom(field))

  def get_index(order_by, field) do
    Enum.find_index(order_by, fn item ->
      case item do
        {f, _} -> f == field
        f when is_binary(f) -> String.to_existing_atom(f) == field
        f -> f == field
      end
    end)
  end

  @doc """
  Returns the current order direction for the given index and `AshPagify.order_by`.

  Following rules are applied:

  - if the `order_by` is `nil`, `nil` is returned
  - if the `order_by` is an atom or a binary, `:asc` is returned
  - if the `order_by` is a tuple, the second element of the tuple is returned
  - if the index is out of bounds, `nil` is returned
  - if the `order_by` is a list, the direction of the element at the given index
  is returned
  """
  @spec get_order_direction(order_by(), non_neg_integer() | nil) :: Ash.Sort.sort_order() | nil
  def get_order_direction(order_by, index)
  def get_order_direction(_, nil), do: :asc
  def get_order_direction(nil, _), do: nil
  def get_order_direction([], _), do: nil
  def get_order_direction(order_by, _) when is_atom(order_by), do: :asc
  def get_order_direction(order_by, _) when is_binary(order_by), do: :asc
  def get_order_direction(order_by, _) when is_tuple(order_by), do: Enum.at(order_by, 1)

  def get_order_direction(order_by, index) do
    case Enum.at(order_by, index, :asc) do
      {_, direction} -> direction
      _ -> :asc
    end
  end

  defguardp is_direction(value)
            when value in [
                   :asc,
                   :asc_nils_first,
                   :desc,
                   :desc_nils_last
                 ]

  defguardp is_asc_direction(value)
            when value in [
                   :asc,
                   :asc_nils_first
                 ]

  defguardp is_desc_direction(value)
            when value in [
                   :desc,
                   :desc_nils_last
                 ]

  defp new_order_direction(0, current_direction, nil), do: reverse_direction(current_direction)

  defp new_order_direction(0, current_direction, {_asc, desc})
       when is_asc_direction(current_direction) and is_desc_direction(desc),
       do: desc

  defp new_order_direction(0, current_direction, {desc, _asc})
       when is_asc_direction(current_direction) and is_desc_direction(desc),
       do: desc

  defp new_order_direction(0, current_direction, {asc, _desc})
       when is_desc_direction(current_direction) and is_asc_direction(asc),
       do: asc

  defp new_order_direction(0, current_direction, {_desc, asc})
       when is_desc_direction(current_direction) and is_asc_direction(asc),
       do: asc

  defp new_order_direction(0, _current_direction, directions) do
    raise InvalidDirectionsError, directions: directions
  end

  defp new_order_direction(_, _, nil), do: :asc
  defp new_order_direction(_, _, {asc, _desc}) when is_direction(asc), do: asc

  defp new_order_direction(_, _, directions) do
    raise InvalidDirectionsError, directions: directions
  end

  defp reverse_direction(:asc), do: :desc
  defp reverse_direction(:asc_nils_first), do: :desc_nils_last
  defp reverse_direction(:desc), do: :asc
  defp reverse_direction(:desc_nils_last), do: :asc_nils_first
end
