defmodule AshPagify.Validation do
  @moduledoc """
  Utilities for validating and transforming full-text search, scoping,
  filtering, ordering, and pagination parameters.
  """

  alias Ash.Error.Query.InvalidLimit
  alias Ash.Error.Query.InvalidOffset
  alias Ash.Resource.Info
  alias AshPagify.Error.Query.InvalidFilterFormParameter
  alias AshPagify.Error.Query.InvalidOrderByParameter
  alias AshPagify.Error.Query.InvalidScopesParameter
  alias AshPagify.Error.Query.InvalidSearchParameter
  alias AshPagify.Error.Query.NoSuchScope
  alias AshPagify.Error.Query.SearchNotImplemented
  alias AshPagify.Misc

  @spec validate_params(Ash.Query.t() | Ash.Resource.t(), map(), Keyword.t()) ::
          {:ok, AshPagify.t()} | {:error, any(), map()}
  def validate_params(query_or_resource, params, opts \\ [])

  def validate_params(%Ash.Query{resource: r}, params, opts) do
    validate_params(r, params, opts)
  end

  def validate_params(resource, %{} = params, opts) do
    opts =
      opts
      |> Keyword.put_new(:for, resource)
      |> Keyword.put_new(:replace_invalid_params?, false)

    opts = Misc.maybe_put_compiled_scopes(resource, opts)
    scopes = Keyword.get(opts, :__compiled_scopes)
    default_scopes = Keyword.get(opts, :__compiled_default_scopes)

    maybe_valid_params =
      params
      |> Misc.atomize_keys(
        keys: ["search", "scopes", "filter_form", "filters", "order_by", "limit", "offset"],
        depth: 1,
        existing?: true
      )
      |> Map.put(:errors, [])
      |> validate_search(opts)
      |> validate_scopes(scopes, default_scopes, opts)
      |> validate_filter_form(opts)
      |> validate_filters(opts)
      |> validate_order_by(opts)
      |> validate_pagination(opts)

    case maybe_valid_params do
      %{errors: []} -> {:ok, struct(%AshPagify{}, maybe_valid_params)}
      %{errors: errors} -> {:error, errors, Map.delete(maybe_valid_params, :errors)}
    end
  end

  # Search validation

  @doc """
  Validates the search attribute in the given parameters.

  In case full_text_search is configured, we validate if the given search
  attribute is a valid full text search attribute.

  If `replace_invalid_params?` is `true`, invalid
  search parameters are removed and an error is added to the `:errors` key in the returned map. If
  `replace_invalid_params?` is `false`, invalid search parameters are not removed and an error is added to
  the `:errors` key in the returned map. Only the first error is added to the `:errors` key.

  If the `:search` key is `nil` or an empty string, it is returned as is.
  """
  @spec validate_search(map(), Keyword.t()) :: map()
  def validate_search(params, opts)

  def validate_search(%{search: nil} = params, _), do: params
  def validate_search(%{search: ""} = params, _), do: params

  def validate_search(%{search: search} = params, opts) when is_binary(search) do
    validate_full_text_search(params, opts)
  end

  def validate_search(params, opts) do
    if Map.get(params, :search) == nil do
      params
    else
      params =
        add_error(params, :search, InvalidSearchParameter.exception(search: params[:search]))

      if Keyword.get(opts, :replace_invalid_params?) do
        Map.put(params, :search, nil)
      else
        params
      end
    end
  end

  @spec validate_full_text_search(map(), Keyword.t()) :: map()
  defp validate_full_text_search(params, opts) do
    resource = Keyword.get(opts, :for)
    valid = valid_full_text_search?(:tsquery, resource)
    valid = valid && valid_full_text_search?(:full_text_search_rank, resource)
    valid = valid && valid_full_text_search?(:full_text_search, resource)

    if valid do
      params
    else
      params =
        add_error(
          params,
          :search,
          SearchNotImplemented.exception(resource: resource)
        )

      if Keyword.get(opts, :replace_invalid_params?) do
        Map.put(params, :search, nil)
      else
        params
      end
    end
  end

  defp valid_full_text_search?(calculation, resource) do
    resource
    |> valid_full_text_search_fields()
    |> Enum.member?(calculation)
  end

  defp valid_full_text_search_fields(resource) do
    filterable_calculations(resource, [
      AshPostgres.Tsquery,
      Ash.Type.Boolean,
      Ash.Type.Float
    ])
  end

  defp filterable_calculations(resource, types) do
    resource
    |> Info.public_calculations()
    |> Enum.filter(&(&1.filterable? and &1.type in types))
    |> Enum.map(& &1.name)
  end

  # Scopes validation

  @doc """
  Validates the scopes in the given parameters.

  If `replace_invalid_params?` is `true`, invalid
  scopes are removed and an error is added to the `:errors` key in the returned map. If
  `replace_invalid_params?` is `false`, invalid scopes are not removed and an error is added to
  the `:errors` key in the returned map. Only the first error is added to the `:errors` key.

  If the `:scopes` key is `nil`, it is returned as is.

  ## Examples

      iex> scopes = %{}
      iex> AshPagify.Validation.validate_scopes(%{}, scopes)
      %{}

      iex> scopes = %{}
      iex> AshPagify.Validation.validate_scopes(%{scopes: nil}, scopes)
      %{scopes: nil}

      iex> scopes = %{}
      iex> %{scopes: scopes} = AshPagify.Validation.validate_scopes(%{scopes: %{role: :admin}}, scopes)
      iex> scopes
      %{role: :admin}

      iex> scopes = %{}
      iex> %{scopes: scopes, errors: errors} = AshPagify.Validation.validate_scopes(%{scopes: %{role: :non_existent}}, scopes)
      iex> scopes
      %{role: :non_existent}
      iex> AshPagify.Error.clear_stacktrace(errors)
      [
        scopes: [
          %AshPagify.Error.Query.NoSuchScope{group: :role, name: :non_existent}
        ]
      ]

      iex> scopes = %{}
      iex> %{scopes: scopes, errors: errors} = AshPagify.Validation.validate_scopes(%{scopes: %{role: :non_existent}}, scopes, nil, replace_invalid_params?: true)
      iex> scopes
      nil
      iex> AshPagify.Error.clear_stacktrace(errors)
      [
        scopes: [
          %AshPagify.Error.Query.NoSuchScope{group: :role, name: :non_existent}
        ]
      ]

      iex> scopes = %{}
      iex> %{scopes: scopes, errors: errors} = AshPagify.Validation.validate_scopes(%{scopes: %{non_existent: :admin}}, scopes)
      iex> scopes
      %{non_existent: :admin}
      iex> AshPagify.Error.clear_stacktrace(errors)
      [
        scopes: [
          %AshPagify.Error.Query.NoSuchScope{group: :non_existent, name: :admin}
        ]
      ]

      iex> scopes = %{}
      iex> %{scopes: scopes, errors: errors} = AshPagify.Validation.validate_scopes(%{scopes: %{non_existent: :admin}}, scopes, nil, replace_invalid_params?: true)
      iex> scopes
      nil
      iex> AshPagify.Error.clear_stacktrace(errors)
      [
        scopes: [
          %AshPagify.Error.Query.NoSuchScope{group: :non_existent, name: :admin}
        ]
      ]
  """
  @spec validate_scopes(map(), map(), map() | nil, Keyword.t()) :: map()
  def validate_scopes(params, scopes, default_scopes \\ nil, opts \\ [])

  def validate_scopes(%{scopes: nil} = params, _, default_scopes, _), do: maybe_put_default_scopes(params, default_scopes)

  def validate_scopes(%{scopes: params_scopes} = params, scopes, default_scopes, opts) when is_map(params_scopes) do
    case parse_scopes(params_scopes, scopes, default_scopes) do
      {:ok, scopes} ->
        Map.put(params, :scopes, scopes)

      {:error, errors, valid_scopes} ->
        params = add_errors(params, :scopes, errors)

        if Keyword.get(opts, :replace_invalid_params?) do
          Map.put(params, :scopes, valid_scopes)
        else
          params
        end
    end
  end

  def validate_scopes(params, _, default_scopes, opts) do
    if Map.get(params, :scopes) == nil do
      maybe_put_default_scopes(params, default_scopes)
    else
      params =
        add_error(params, :scopes, InvalidScopesParameter.exception(scopes: params[:scopes]))

      if Keyword.get(opts, :replace_invalid_params?) do
        params
        |> Map.put(:scopes, nil)
        |> maybe_put_default_scopes(default_scopes)
      else
        params
      end
    end
  end

  defp parse_scopes(params_scopes, scopes, default_scopes) do
    {valid_scopes, errors} =
      Enum.reduce(params_scopes, {%{}, []}, fn {group, name}, {valid_scopes, errors} ->
        case validate_scope(group, name, scopes) do
          {:ok, valid_group, valid_name} ->
            {Map.put(valid_scopes, valid_group, valid_name), errors}

          :error ->
            {valid_scopes, [NoSuchScope.exception(group: group, name: name) | errors]}
        end
      end)

    valid_scopes =
      valid_scopes
      |> Misc.coerce_maybe_empty_map()
      |> ensure_default_scopes(default_scopes)

    if errors == [] do
      {:ok, valid_scopes}
    else
      {:error, errors, valid_scopes}
    end
  end

  defp ensure_default_scopes(nil, nil), do: nil
  defp ensure_default_scopes(scopes, nil), do: scopes
  defp ensure_default_scopes(nil, default_scopes), do: ensure_default_scopes(%{}, default_scopes)

  defp ensure_default_scopes(scopes, default_scopes) do
    Map.merge(default_scopes, scopes)
  end

  defp maybe_put_default_scopes(params, nil), do: params

  defp maybe_put_default_scopes(params, default_scopes) do
    scopes =
      params
      |> Map.get(:scopes)
      |> Misc.coerce_maybe_empty_map()
      |> ensure_default_scopes(default_scopes)

    if scopes == nil do
      params
    else
      Map.put(params, :scopes, scopes)
    end
  end

  defp validate_scope(group, name, scopes) when is_binary(group) and is_binary(name) do
    validate_scope(
      String.to_existing_atom(group),
      String.to_existing_atom(name),
      scopes
    )
  rescue
    _ -> :error
  end

  defp validate_scope(group, name, scopes) do
    if scope_name_exists?(group, name, scopes) do
      {:ok, group, name}
    else
      :error
    end
  end

  defp scope_name_exists?(group, name, scopes) do
    scope_group_exists?(group, scopes) and
      Enum.find(scopes[group], &(&1.name == name)) != nil
  end

  defp scope_group_exists?(group, scopes), do: Map.has_key?(scopes, group)

  # Form filter validation

  @doc """
  Validates the form filter in the given parameters.

  Uses `AshPagify.FormFilter.validate/3` to parse the form filter.

  If `replace_invalid_params?` is `true`, invalid
  filter_form parameters are removed and an error is added to the `:errors` key
  in the returned map. If `replace_invalid_params?` is `false`, invalid
  filter_form parameters are not removed and an error is added to the `:errors`
  key in the returned map.

  If the `:filter_form` key is `nil`, it is returned as is.

  ## Examples

      iex> AshPagify.Validation.validate_filter_form(%{}, for: Post)
      %{}

      iex> AshPagify.Validation.validate_filter_form(%{filter_form: nil}, for: Post)
      %{filter_form: nil}

      iex> %{filter_form: filter_form} = AshPagify.Validation.validate_filter_form(%{filter_form: %{}}, for: Post)
      iex> filter_form
      %{}

      iex> %{filter_form: filter_form} = AshPagify.Validation.validate_filter_form(%{filter_form: %{}}, for: Post, replace_invalid_params?: true)
      iex> filter_form
      %{}

      iex> %{filter_form: filter_form, errors: errors} = AshPagify.Validation.validate_filter_form(%{filter_form:  %{"field" => "non_existent", "operator" => "eq", "value" => "Post 1"}}, for: Post)
      iex> filter_form
      %{"field" => "non_existent", "operator" => "eq", "value" => "Post 1"}
      iex> errors
      [filter_form: [{:field, {"No such field non_existent", []}}]]

      iex> %{filter_form: filter_form, errors: errors} = AshPagify.Validation.validate_filter_form(%{filter_form:  %{"field" => "non_existent", "operator" => "eq", "value" => "Post 1"}}, for: Post, replace_invalid_params?: true)
      iex> filter_form
      %{}
      iex> errors
      [filter_form: [{:field, {"No such field non_existent", []}}]]
  """
  @spec validate_filter_form(map(), Keyword.t()) :: map()
  def validate_filter_form(params, opts)
  def validate_filter_form(%{filter_form: nil} = params, _), do: params

  def validate_filter_form(%{filter_form: %{} = filter_form} = params, _) when filter_form == %{}, do: params

  def validate_filter_form(%{filter_form: %{}} = params, opts) do
    filter_form =
      opts
      |> Keyword.get(:for)
      |> AshPagify.FilterForm.new()
      |> AshPagify.FilterForm.validate(Map.get(params, :filter_form, %{}))

    case filter_form do
      %{valid?: false} ->
        errors = AshPagify.FilterForm.errors(filter_form)
        params = add_errors(params, :filter_form, errors)

        if Keyword.get(opts, :replace_invalid_params?) do
          valid_components = Enum.filter(filter_form.components, & &1.valid?)

          filter_form =
            AshPagify.FilterForm.params_for_query(%{filter_form | components: valid_components})

          Map.put(params, :filter_form, filter_form)
        else
          params
        end

      _ ->
        params
    end
  end

  def validate_filter_form(params, opts) do
    if Map.get(params, :filter_form) == nil do
      params
    else
      params =
        add_error(
          params,
          :filter_form,
          InvalidFilterFormParameter.exception(filter_form: params[:filter_form])
        )

      if Keyword.get(opts, :replace_invalid_params?) do
        Map.put(params, :filter_form, nil)
      else
        params
      end
    end
  end

  # Filter validation

  @doc """
  Validates the filters in the given parameters.

  If `replace_invalid_params?` is `true`, invalid
  filters are removed and an error is added to the `:errors` key in the returned map. If
  `replace_invalid_params?` is `false`, invalid filters are not removed and an error is added to
  the `:errors` key in the returned map. Only the first error is added to the `:errors` key.

  If the `:filters` key is `nil`, it is returned as is.

  ## Examples

      iex> AshPagify.Validation.validate_filters(%{}, for: Post)
      %{}

      iex> AshPagify.Validation.validate_filters(%{filters: nil}, for: Post)
      %{filters: nil}

      iex> %{filters: filters} = AshPagify.Validation.validate_filters(%{filters: [%{name: "Post 1"}]}, for: Post)
      iex> filters
      #Ash.Filter<name == "Post 1">

      iex> %{filters: filters, errors: errors} = AshPagify.Validation.validate_filters(%{filters: 1}, for: Post, replace_invalid_params?: true)
      iex> filters
      nil
      iex> AshPagify.Error.clear_stacktrace(errors)
      [
        filters: [
          %Ash.Error.Query.InvalidFilterValue{value: 1}
        ]
      ]

      iex> %{filters: filters, errors: errors} = AshPagify.Validation.validate_filters(%{filters: 1}, for: Post)
      iex> filters
      1
      iex> AshPagify.Error.clear_stacktrace(errors)
      [
        filters: [
          %Ash.Error.Query.InvalidFilterValue{value: 1}
        ]
      ]
  """
  @spec validate_filters(map(), Keyword.t()) :: map()
  def validate_filters(params, opts)
  def validate_filters(%{filters: nil} = params, _), do: params

  def validate_filters(%{filters: filters} = params, opts) when is_map(filters) or is_list(filters) do
    case Ash.Filter.parse_input(Keyword.get(opts, :for), filters) do
      {:ok, filters} ->
        Map.put(params, :filters, filters)

      {:error, error} ->
        if Keyword.get(opts, :replace_invalid_params?) do
          replace_invalid_filters(filters, params, Keyword.get(opts, :for))
        else
          add_error(params, :filters, error)
        end
    end
  end

  def validate_filters(%{filters: filters} = params, opts) do
    case Ash.Filter.parse_input(Keyword.get(opts, :for), filters) do
      {:ok, filters} ->
        Map.put(params, :filters, filters)

      {:error, error} ->
        params = add_error(params, :filters, error)

        if Keyword.get(opts, :replace_invalid_params?) do
          Map.put(params, :filters, nil)
        else
          params
        end
    end
  end

  def validate_filters(params, _), do: params

  defp replace_invalid_filters(filters, params, resource) do
    case Ash.Filter.parse_input(resource, filters) do
      {:ok, filters} ->
        if Ash.Filter.list_predicates(filters) == [] do
          Map.put(params, :filters, nil)
        else
          Map.put(params, :filters, filters)
        end

      {:error, error} ->
        params = add_error(params, :filters, error)
        filters = remove_key(filters, error.field)
        replace_invalid_filters(filters, params, resource)
    end
  end

  defp remove_key(map, key) when is_map(map) do
    if Map.has_key?(map, key) do
      Map.delete(map, key)
    else
      Map.new(
        Enum.map(map, fn {k, v} ->
          {k, remove_key(v, key)}
        end)
      )
    end
  end

  defp remove_key(list, key) when is_list(list) do
    Enum.map(list, fn item -> remove_key(item, key) end)
  end

  defp remove_key(value, _), do: value

  # Order by validation

  @doc """
  Validates the order by in the given parameters.

  If `replace_invalid_params?` is `true`, invalid
  order by values are removed and an error is added to the `:errors` key in the returned map. If
  `replace_invalid_params?` is `false`, invalid order by values are not removed and an error is added
  to the `:errors` key in the returned map. Only the first error is added to the `:errors` key.

  If the `:order_by` key is `nil`, it is returned as is.

  ## Examples

      iex> AshPagify.Validation.validate_order_by(%{}, for: Post)
      %{}

      iex> AshPagify.Validation.validate_order_by(%{order_by: nil}, for: Post)
      %{order_by: nil}

      iex> %{order_by: order_by} = AshPagify.Validation.validate_order_by(%{order_by: ["name"]}, for: Post)
      iex> order_by
      [name: :asc]

      iex> %{order_by: order_by} = AshPagify.Validation.validate_order_by(%{order_by: "++name"}, for: Post)
      iex> order_by
      [name: :asc_nils_first]

      iex> %{order_by: order_by} = AshPagify.Validation.validate_order_by(%{order_by: "name,--comments_count"}, for: Post)
      iex> order_by
      [name: :asc, comments_count: :desc_nils_last]

      iex> %{order_by: order_by, errors: errors} = AshPagify.Validation.validate_order_by(%{order_by: "--name,non_existent"}, for: Post, replace_invalid_params?: true)
      iex> order_by
      [name: :desc_nils_last]
      iex> AshPagify.Error.clear_stacktrace(errors)
      [
        order_by: [
          %Ash.Error.Query.NoSuchField{field: "non_existent", resource: Post}
        ]
      ]
  """
  @spec validate_order_by(map(), Keyword.t()) :: map()
  def validate_order_by(params, opts)
  def validate_order_by(%{order_by: nil} = params, _), do: params

  def validate_order_by(%{order_by: order_by} = params, opts) when is_atom(order_by) do
    validate_order_by(%{params | order_by: Atom.to_string(order_by)}, opts)
  end

  def validate_order_by(%{order_by: order_by} = params, opts) when is_binary(order_by) do
    validate_order_by(%{params | order_by: String.split(order_by, ",")}, opts)
  end

  def validate_order_by(%{order_by: order_by} = params, opts) when is_list(order_by) do
    case Ash.Sort.parse_input(Keyword.get(opts, :for), order_by) do
      {:ok, order_by} ->
        Map.put(params, :order_by, order_by)

      {:error, error} ->
        if Keyword.get(opts, :replace_invalid_params?) do
          replace_invalid_order_by(order_by, params, Keyword.get(opts, :for))
        else
          add_error(params, :order_by, error)
        end
    end
  end

  def validate_order_by(%{order_by: order_by} = params, opts) when is_map(order_by) do
    params = add_error(params, :order_by, InvalidOrderByParameter.exception(order_by: order_by))

    if Keyword.get(opts, :replace_invalid_params?) do
      Map.put(params, :order_by, nil)
    else
      params
    end
  end

  def validate_order_by(params, opts) do
    if Map.get(params, :order_by) == nil do
      params
    else
      params =
        add_error(
          params,
          :order_by,
          InvalidOrderByParameter.exception(order_by: params[:order_by])
        )

      if Keyword.get(opts, :replace_invalid_params?) do
        Map.put(params, :order_by, nil)
      else
        params
      end
    end
  end

  defp replace_invalid_order_by(order_by, params, resource) do
    case Ash.Sort.parse_input(resource, order_by) do
      {:ok, order_by} ->
        if order_by == [] do
          Map.put(params, :order_by, nil)
        else
          Map.put(params, :order_by, order_by)
        end

      {:error, error} ->
        params = add_error(params, :order_by, error)
        order_by = List.delete(order_by, error.field)
        replace_invalid_order_by(order_by, params, resource)
    end
  end

  # Pagination validation

  @doc """
  Validates the pagination parameters in the given parameters.

  If `replace_invalid_params?` is `true`,
  invalid pagination parameters are removed / replaced and an error is added to the `:errors` key in
  the returned map. If `replace_invalid_params?` is `false`, invalid pagination parameters are not
  removed and an error is added to the `:errors` key in the returned map.

  If the `:limit` key is `nil`, the default_limit value is applied.

  If the `:offset` key is `nil`, it is returned as is.

  ## Examples

      iex> AshPagify.Validation.validate_pagination(%{}, for: Post)
      %{limit: 15, offset: 0}

      iex> AshPagify.Validation.validate_pagination(%{limit: nil}, for: Post)
      %{limit: 15, offset: 0}

      iex> %{limit: limit} = AshPagify.Validation.validate_pagination(%{limit: 10}, for: Post)
      iex> limit
      10

      iex> %{limit: limit, errors: errors} = AshPagify.Validation.validate_pagination(%{limit: 0}, for: Post, replace_invalid_params?: true)
      iex> limit
      15
      iex> AshPagify.Error.clear_stacktrace(errors)
      [
        limit: [
          %Ash.Error.Query.InvalidLimit{limit: 0}
        ]
      ]

      iex> %{limit: limit} = AshPagify.Validation.validate_pagination(%{limit: 100}, for: Post)
      iex> limit
      100

      iex> %{limit: limit, errors: errors} = AshPagify.Validation.validate_pagination(%{limit: -1}, for: Post, replace_invalid_params?: true)
      iex> limit
      15
      iex> AshPagify.Error.clear_stacktrace(errors)
      [
        limit: [
          %Ash.Error.Query.InvalidLimit{limit: -1}
        ]
      ]

      iex> %{offset: offset} = AshPagify.Validation.validate_pagination(%{offset: 10}, for: Post)
      iex> offset
      10

      iex> %{offset: offset, errors: errors} = AshPagify.Validation.validate_pagination(%{offset: -1}, for: Post, replace_invalid_params?: true)
      iex> offset
      0
      iex> AshPagify.Error.clear_stacktrace(errors)
      [
        offset: [
          %Ash.Error.Query.InvalidOffset{offset: -1}
        ]
      ]

      iex> %{offset: offset, errors: errors} = AshPagify.Validation.validate_pagination(%{offset: -1}, for: Post)
      iex> offset
      -1
      iex> AshPagify.Error.clear_stacktrace(errors)
      [
        offset: [
          %Ash.Error.Query.InvalidOffset{offset: -1}
        ]
      ]
  """
  @spec validate_pagination(map(), Keyword.t()) :: map()
  def validate_pagination(params, opts) do
    replace_invalid_params? = Keyword.get(opts, :replace_invalid_params?, false)

    params
    |> validate_and_maybe_delete(:limit, &validate_limit/2, opts, replace_invalid_params?)
    |> put_default_limit(opts)
    |> validate_and_maybe_delete(:offset, &validate_offset/2, opts, replace_invalid_params?)
    |> put_default_offset()
  end

  defp validate_and_maybe_delete(params, key, validate_func, opts, true) do
    validated_params = validate_func.(params, opts)

    case validated_params do
      {:ok, validated_params} -> validated_params
      {:error, validated_params} -> Map.put(validated_params, key, nil)
    end
  end

  defp validate_and_maybe_delete(params, _key, validate_func, opts, _) do
    {_, validated_params} = validate_func.(params, opts)
    validated_params
  end

  defp validate_limit(%{limit: nil} = params, _opts), do: {:ok, params}

  defp validate_limit(%{limit: limit} = params, opts) when is_integer(limit) do
    if limit > 0 do
      max_limit = Keyword.get(opts, :max_limit, Misc.get_option(:max_limit, opts))
      validate_within_max_limit(params, max_limit)
    else
      {:error, add_error(params, :limit, InvalidLimit.exception(limit: limit))}
    end
  end

  defp validate_limit(%{limit: limit} = params, opts) when is_binary(limit) do
    case Integer.parse(limit) do
      {limit_number, ""} -> validate_limit(Map.put(params, :limit, limit_number), opts)
      _ -> {:error, add_error(params, :limit, InvalidLimit.exception(limit: limit))}
    end
  end

  defp validate_limit(params, _opts) do
    case Map.get(params, :limit) do
      nil -> {:ok, params}
      limit -> {:error, add_error(params, :limit, InvalidLimit.exception(limit: limit))}
    end
  end

  defp validate_within_max_limit(params, nil) do
    {:ok, params}
  end

  defp validate_within_max_limit(%{limit: limit} = params, max_limit) do
    if limit <= max_limit do
      {:ok, params}
    else
      {:error, add_error(params, :limit, InvalidLimit.exception(limit: limit))}
    end
  end

  defp put_default_limit(%{limit: nil} = params, opts) do
    Map.put(params, :limit, default_limit(opts))
  end

  defp put_default_limit(params, opts) do
    Map.put_new_lazy(params, :limit, fn -> default_limit(opts) end)
  end

  defp default_limit(opts) do
    if Keyword.get(opts, :default_limit) == false do
      nil
    else
      Misc.get_option(:default_limit, opts)
    end
  end

  defp validate_offset(%{offset: offset} = params, _opts) when is_integer(offset) do
    if offset >= 0 do
      {:ok, params}
    else
      {:error, add_error(params, :offset, InvalidOffset.exception(offset: offset))}
    end
  end

  defp validate_offset(%{offset: offset} = params, opts) when is_binary(offset) do
    case Integer.parse(offset) do
      {offset_number, ""} -> validate_offset(Map.put(params, :offset, offset_number), opts)
      _ -> {:error, add_error(params, :offset, InvalidOffset.exception(offset: offset))}
    end
  end

  defp validate_offset(params, _opts), do: {:ok, params}

  defp put_default_offset(%{offset: nil} = params) do
    Map.put(params, :offset, 0)
  end

  defp put_default_offset(params) do
    Map.put_new(params, :offset, 0)
  end

  defp add_errors(params, key, ash_errors) when is_list(ash_errors) do
    params = Map.put_new_lazy(params, :errors, fn -> [] end)

    errors =
      params
      |> Map.get(:errors, [])
      |> Keyword.put(key, ash_errors)

    Map.put(params, :errors, errors)
  end

  defp add_error(params, key, ash_error) do
    params = Map.put_new_lazy(params, :errors, fn -> [] end)

    errors =
      params
      |> Map.get(:errors, [])
      |> Keyword.put(key, [ash_error | Keyword.get(params.errors, key, [])])

    Map.put(params, :errors, errors)
  end
end
