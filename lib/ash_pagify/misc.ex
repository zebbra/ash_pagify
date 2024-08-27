defmodule AshPagify.Misc do
  @moduledoc """
  Miscellaneous functions for AshPagify.
  """

  import AshPagify.Guards, only: [is_valid_option: 1]

  @doc """
  Returns the option with the given key.

  The look-up order is:

  1. the keyword list passed as the second argument
  2. the Ash.Resource resource, if the passed list includes the `:for` option
  3. the application environment
  4. the AshPagify default value if defined
  5. the default passed as the last argument

  For the `:scopes` option, the function will deep merge the options
  in reverse order (keyword overrides resource, resource overrides global, etc.)

  ## Examples for `:scopes`

      iex> alias AshPagify.Factory.Post
      iex> opts = [
      ...>   scopes: %{
      ...>     role: [
      ...>       %{name: :user, filter: %{name: "changed"}},
      ...>       %{name: :other, filter: %{name: "other"}}
      ...>     ],
      ...>     status: [
      ...>       %{name: :all, filter: nil, default?: true},
      ...>       %{name: :active, filter: %{age: %{lt: 10}}},
      ...>       %{name: :inactive, filter: %{age: %{gte: 10}}}
      ...>     ]
      ...>   },
      ...>   for: Post
      ...> ]
      iex> get_option(:scopes, opts, %{
      ...>   role: [
      ...>     %{name: :default, filter: %{author: "Default"}}
      ...>   ]
      ...> })
      %{
        role: [
          %{name: :admin, filter: %{author: "John"}},
          %{name: :user, filter: %{name: "changed"}},
          %{name: :other, filter: %{name: "other"}},
          %{name: :default, filter: %{author: "Default"}}
        ],
        status: [
          %{name: :inactive, filter: %{age: %{gte: 10}}},
          %{name: :all, filter: nil, default?: true},
          %{name: :active, filter: %{age: %{lt: 10}}}
        ]
      }
  """
  @spec get_option(atom(), Keyword.t(), any()) :: any()
  def get_option(key, opts \\ [], default \\ nil)

  def get_option(key, _opts, _default) when is_valid_option(key) == false do
    raise ArgumentError, "Unknown option: #{inspect(key)}"
  end

  def get_option(:scopes, opts, default) do
    opts_scopes = Keyword.get(opts, :scopes, %{})
    resource_scopes = resource_option(opts[:for], :scopes) || %{}
    global_scopes = global_option(:scopes) || %{}
    default_scopes = Keyword.get(AshPagify.default_opts(), :scopes, %{})
    default = default || %{}

    default
    |> merge_scopes(default_scopes)
    |> merge_scopes(global_scopes)
    |> merge_scopes(resource_scopes)
    |> merge_scopes(opts_scopes)
  end

  def get_option(key, opts, default) do
    with nil <- opts[key],
         nil <- resource_option(opts[:for], key),
         nil <- global_option(key) do
      Keyword.get(AshPagify.default_opts(), key, default)
    end
  end

  @doc """
  Returns the resource option derived from a map or a function reference in the resource
  ash_pagfiy_options function.
  """
  @spec resource_option(atom(), atom()) :: any()
  def resource_option(resource, key)
  def resource_option(nil, _key), do: nil
  def resource_option(resource, _key) when is_atom(resource) == false, do: nil

  def resource_option(resource, key) when key == :default_order do
    resource |> Ash.Resource.Info.preparations() |> resource_preparation_sort()
  end

  def resource_option(resource, key) do
    resolve_opts_func_or_map(:resource, key, resource)
  end

  @doc """
  Returns the global option derived from a map or a function referenced in the application
  environment.
  """
  @spec global_option(atom()) :: any()
  def global_option(key) when is_atom(key) do
    resolve_opts_func_or_map(:global, key)
  end

  defp merge_scopes(nil, default), do: default

  defp merge_scopes(opts, default) do
    Map.merge(default, opts, fn _key, default_val, opts_val ->
      merge_scope_lists(default_val, opts_val)
    end)
  end

  defp merge_scope_lists(default_list, opts_list) do
    default_map = Map.new(default_list, &{&1[:name], &1})
    opts_map = Map.new(opts_list, &{&1[:name], &1})

    merged_map =
      Map.merge(default_map, opts_map, fn _key, default_item, opts_item ->
        Map.merge(opts_item, default_item)
      end)

    merged_map |> Map.values() |> Enum.reverse()
  end

  defp resource_preparation_sort(preparations, default \\ nil)
  defp resource_preparation_sort([], default), do: default

  defp resource_preparation_sort([%Ash.Resource.Preparation{preparation: {_, [options: [sort: sort]]}} | _rest], _default)
       when is_list(sort) do
    sort
  end

  defp resource_preparation_sort([_ | rest], default) do
    resource_preparation_sort(rest, default)
  end

  defp resolve_opts_func_or_map(scope, key, resource \\ nil) do
    case opts_func_or_map(scope, key, resource) do
      {module, func} -> apply(module, func, [])
      config -> config
    end
  end

  defp opts_func_or_map(:global, key, nil) do
    :ash_pagify
    |> Application.get_env(key, nil)
    |> maybe_get_opts(key)
  end

  defp opts_func_or_map(:resource, key, resource) do
    if Keyword.has_key?(resource.__info__(:functions), :ash_pagify_options) do
      resource.ash_pagify_options()
      |> Map.get(key)
      |> maybe_get_opts(key)
    end
  end

  defp maybe_get_opts(nil, _), do: nil

  defp maybe_get_opts(config, key) when key in [:pagination, :table] do
    Keyword.get(config, :opts)
  end

  defp maybe_get_opts(config, _), do: config

  @doc """
  Deep merges two lists, preferring values from the right list.

  If a key exists in both lists, and both values are lists as well,
  these can be merged recursively. If a key exists in both lists,
  but at least one of the values is NOT a list, we fall back to
  standard merge behavior, preferring the value on the right.

  Example:

      iex> list_merge(
      ...>   [aria: [role: "navigation"]],
      ...>   [aria: [label: "pagination"]]
      ...> )
      [aria: [role: "navigation", label: "pagination"]]

      iex> list_merge(
      ...>   [class: "a"],
      ...>   [class: "b"]
      ...> )
      [class: "b"]
  """
  @spec list_merge(keyword, keyword) :: keyword
  def list_merge(left, right) when is_list(left) and is_list(right) do
    Keyword.merge(left, right, &do_list_merge/3)
  end

  # Key exists in both lists, and both values are lists as well.
  # These can be merged recursively.
  defp do_list_merge(_key, left, right) when is_list(left) and is_list(right) do
    list_merge(left, right)
  end

  # Key exists in both lists, but at least one of the values is
  # NOT a list. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp do_list_merge(_key, _left, right), do: right

  @doc """
  Deeply merges two maps, preferring values from the right map.

  If a key exists in both maps, and both values are maps as well,
  these can be merged recursively. If a key exists in both maps,
  but at least one of the values is NOT a map, we fall back to
  standard merge behavior, preferring the value on the right.

  Example:

      iex> AshPagify.Misc.map_merge(%{a: 1, b: %{c: 2}}, %{b: %{d: 3}})
      %{a: 1, b: %{c: 2, d: 3}}

  one level of maps without conflict
      iex> AshPagify.Misc.map_merge(%{a: 1}, %{b: 2})
      %{a: 1, b: 2}

  two levels of maps without conflict
      iex> AshPagify.Misc.map_merge(%{a: %{b: 1}}, %{a: %{c: 3}})
      %{a: %{b: 1, c: 3}}

  three levels of maps without conflict
      iex> AshPagify.Misc.map_merge(%{a: %{b: %{c: 1}}}, %{a: %{b: %{d: 2}}})
      %{a: %{b: %{c: 1, d: 2}}}

  non-map value in left
      iex> AshPagify.Misc.map_merge(%{a: 1}, %{a: %{b: 2}})
      %{a: %{b:  2}}

  non-map value in right
      iex> AshPagify.Misc.map_merge(%{a: %{b: 1}}, %{a: 2})
      %{a: 2}

  non-map value in both
      iex> AshPagify.Misc.map_merge(%{a: 1}, %{a: 2})
      %{a: 2}
  """
  @spec map_merge(map(), map()) :: map()
  def map_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, &do_map_merge/3)
  end

  # Key exists in both maps, and both values are maps as well.
  # These can be merged recursively.
  defp do_map_merge(_key, left, right) when is_map(left) and is_map(right) do
    map_merge(left, right)
  end

  # Key exists in both maps, but at least one of the values is
  # NOT a map. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp do_map_merge(_key, _left, right) do
    right
  end

  @doc """
  Deeply merges two maps or lists, preferring values from the right map or list.

  If a key exists in both maps or lists, and both values are maps or lists as well,
  these can be merged recursively. If a key exists in both maps or lists,
  but at least one of the values is NOT a map or list, we fall back to
  standard merge behavior, preferring the value on the right.

  Example:

      iex> AshPagify.Misc.deep_merge(%{a: 1, b: %{c: 2}}, %{b: %{d: 3}})
      %{a: 1, b: %{c: 2, d: 3}}

  one level of maps without conflict

      iex> AshPagify.Misc.deep_merge(%{a: 1}, %{b: 2})
      %{a: 1, b: 2}

  two levels of maps without conflict

      iex> AshPagify.Misc.deep_merge(%{a: [%{b: 1}]}, %{a: [%{c: 3}]})
      %{a: [%{b: 1}, %{c: 3}]}

  three levels of maps without conflict

      iex> AshPagify.Misc.deep_merge(%{a: %{b: %{c: 1}}}, %{a: %{b: %{d: 2}}})
      %{a: %{b: %{c: 1, d: 2}}}

  non-map value in left

      iex> AshPagify.Misc.deep_merge(%{a: 1}, %{a: %{b: 2}})
      %{a: %{b:  2}}

  non-map value in right

      iex> AshPagify.Misc.deep_merge(%{a: %{b: 1}}, %{a: 2})
      %{a: 2}

  non-map value in both

      iex> AshPagify.Misc.deep_merge(%{a: 1}, %{a: 2})
      %{a: 2}

  map of list

      iex> AshPagify.Misc.deep_merge(%{a: [1, 2]}, %{a: [2, 3]})
      %{a: [1, 2, 3]}

  map of list of map

      iex> AshPagify.Misc.deep_merge(%{a: [%{b: 1}, %{c: 2}]}, %{a: [%{c: 3}, %{d: 4}]})
      %{a: [%{b: 1}, %{c: 3}, %{d: 4}]}

  map of different types

      iex> AshPagify.Misc.deep_merge(%{a: [1, 2]}, %{a: %{b: 2}})
      %{a: %{b: 2}}

  map of list of different types

      iex> AshPagify.Misc.deep_merge(%{a: [1, 2]}, %{a: [%{b: 2}]})
      %{a: [1, 2, %{b: 2}]}
  """
  @spec deep_merge(map() | list(), map() | list()) :: map() | list()
  def deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, val1, val2 ->
      deep_merge(val1, val2)
    end)
  end

  def deep_merge(left, right) when is_list(left) and is_list(right) do
    merge_list_elements(left, right)
  end

  def deep_merge(_left, right) do
    right
  end

  defp merge_list_elements(left, right) do
    left
    |> Enum.map(&{find_matching(&1, right), &1})
    |> Enum.map(fn
      {nil, elem1} -> elem1
      {elem2, _elem1} -> deep_merge(elem2, elem2)
    end)
    |> Enum.concat(right)
    |> Enum.uniq()
    |> Enum.reject(fn elem -> elem == %{} end)
  end

  defp find_matching(elem, list) do
    Enum.find(list, fn e -> maybe_map_key_matching?(e, elem) end)
  end

  defp maybe_map_key_matching?(left, right) when is_map(left) and is_map(right) do
    Map.keys(left) == Map.keys(right)
  end

  defp maybe_map_key_matching?(left, right) do
    left == right
  end

  @doc """
  Walks a map or list and applies a serializer to the keys.

  The serializer function receives the key and the opts. The serializer function
  should return the new key.

  The walk function will walk the map or list and apply the serializer to the
  keys. If the depth is specified and it is reached, the serializer will not
  be applied to the keys at that depth.

  The serializer function can be used to convert the keys to atoms, strings, or
  any other format.

  ## Example

      iex> walk(%{"a" => 1, "b" => %{"c" => 3}}, fn key, _opts -> String.to_atom(key) end)
      %{a: 1, b: %{c: 3}}

      iex> walk(%{"a" => 1, "b" => %{"c" => 3}}, fn key, _opts -> String.to_atom(key) end, depth: 1)
      %{b: %{"c" => 3}, a: 1}
  """

  @spec walk(map() | list(), (term(), Keyword.t() -> term()), Keyword.t(), integer()) ::
          term()
  def walk(map_or_list, serializer \\ &default_serializer/2, opts \\ [], current_depth \\ 1)

  def walk(%{__struct__: _} = struct, _, _, _), do: struct

  def walk(%{} = map, serializer, opts, current_depth) do
    depth = Keyword.get(opts, :depth)

    Map.new(map, fn {k, v} ->
      if is_nil(depth) == false and current_depth >= depth do
        {serializer.(k, opts), v}
      else
        {serializer.(k, opts), walk(v, serializer, opts, current_depth + 1)}
      end
    end)
  end

  def walk([head | rest], serializer, opts, current_depth) do
    [
      walk(head, serializer, opts, current_depth)
      | walk(rest, serializer, opts, current_depth)
    ]
  end

  def walk(other_type, _, _, _), do: other_type

  defp default_serializer(key, _opts), do: key

  @doc """
  Convert map string keys to :atom keys. This is useful when
  you have a map that was created from JSON or other external
  source and you want to convert the keys to atoms.

  You can specify a list of keys to convert or a depth to which
  to convert keys. If you specify a depth of 1, only the top
  level keys will be converted. If you specify a depth of 2, the
  top level keys and the keys of any maps in the top level will
  be converted. And so on.

  If you set the existing? option to true, the function will use
  the `String.to_existing_atom/1` function to convert the keys.

  List of options:

  - `keys`: A list of keys to convert. If a key is not in the list,
    it will not be converted. Default is an empty list and all keys
    will be converted.
  - `depth`: The depth to which to convert keys. Default is nil and
    all keys will be converted.
  - `existing?`: If true, the function will use `String.to_existing_atom/1`
    to convert the keys. Default is false.

  ## Example

      iex> AshPagify.Misc.atomize_keys(%{"a" => 1, "b" => 2})
      %{a: 1, b: 2}

      iex> AshPagify.Misc.atomize_keys(%{"a" => 1, "b" => %{"c" => 3}})
      %{a: 1, b: %{c: 3}}

      iex> AshPagify.Misc.atomize_keys(%{"a" => 1, "b" => %{"c" => 3}}, keys: ["b"])
      %{"a" => 1, b: %{"c" => 3}}

      iex> AshPagify.Misc.atomize_keys(%{"a" => 1, "b" => %{"c" => 3}}, keys: ["b", "c"])
      %{"a" => 1, b: %{c: 3}}

      iex> AshPagify.Misc.atomize_keys(%{"a" => 1, "b" => %{"c" => 3}}, keys: ["b", "d"], depth: 1)
      %{"a" => 1, b: %{"c" => 3}}

      iex> AshPagify.Misc.atomize_keys(%{"a" => 1, "b" => %{"c" => 3}}, keys: ["b", "c"], depth: 2)
      %{"a" => 1, b: %{c: 3}}
  """
  @spec atomize_keys(map() | struct(), Keyword.t()) :: map() | struct()
  def atomize_keys(map_or_struct, opts \\ [])
  def atomize_keys(nil, _), do: nil
  def atomize_keys(%{__struct__: _} = struct, _), do: struct

  def atomize_keys(%{} = map, opts) do
    walk(map, &atomize_key/2, opts)
  end

  def atomize_keys(not_a_map, _), do: not_a_map

  # sobelow_skip ["DOS.StringToAtom"]
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp atomize_key(key, opts) when is_binary(key) do
    existing? = Keyword.get(opts, :existing?)
    keys = Keyword.get(opts, :keys)

    list? = is_list(keys)
    member? = if list?, do: Enum.member?(keys, key), else: false

    cond do
      list? and member? and existing? -> String.to_existing_atom(key)
      list? and member? -> String.to_atom(key)
      list? and member? == false -> key
      existing? -> String.to_existing_atom(key)
      true -> String.to_atom(key)
    end
  end

  defp atomize_key(key, _), do: key

  @doc """
  Convert map :atom keys to string keys.

  You can specify a list of keys to convert or a depth to which
  to convert keys. If you specify a depth of 1, only the top
  level keys will be converted. If you specify a depth of 2, the
  top level keys and the keys of any maps in the top level will
  be converted. And so on.

  List of options:

  - `keys`: A list of keys to convert. If a key is not in the list,
    it will not be converted. Default is an empty list and all keys
    will be converted.
  - `depth`: The depth to which to convert keys. Default is nil and
    all keys will be converted.

  ## Example

      iex> AshPagify.Misc.stringify_keys(%{a: 1, b: 2})
      %{"a" => 1, "b" => 2}

      iex> AshPagify.Misc.stringify_keys(%{a: 1, b: %{c: 3}})
      %{"a" => 1, "b" => %{"c" => 3}}

      iex> AshPagify.Misc.stringify_keys(%{a: 1, b: %{c: 3}}, keys: [:b])
      %{:a => 1, "b" => %{c: 3}}

      iex> AshPagify.Misc.stringify_keys(%{a: 1, b: %{c: 3}}, keys: [:b, :c])
      %{:a => 1, "b" => %{"c" => 3}}

      iex> AshPagify.Misc.stringify_keys(%{a: 1, b: %{c: 3}}, keys: [:b, :d], depth: 1)
      %{:a => 1, "b" => %{c: 3}}

      iex> AshPagify.Misc.stringify_keys(%{a: 1, b: %{c: 3}}, keys: [:b, :c], depth: 2)
      %{:a => 1, "b" => %{"c" => 3}}
  """
  @spec stringify_keys(map() | struct(), Keyword.t()) :: map() | struct()
  def stringify_keys(map_or_struct, opts \\ [])
  def stringify_keys(nil, _), do: nil
  def stringify_keys(%{__struct__: _} = struct, _), do: struct

  def stringify_keys(%{} = map, opts) do
    walk(map, &stringify_key/2, opts)
  end

  def stringify_keys(not_a_map, _), do: not_a_map

  defp stringify_key(key, opts) when is_atom(key) do
    keys = Keyword.get(opts, :keys)

    list? = is_list(keys)
    member? = if list?, do: Enum.member?(keys, key), else: false

    cond do
      list? and member? -> Atom.to_string(key)
      list? and member? == false -> key
      true -> Atom.to_string(key)
    end
  end

  defp stringify_key(key, _), do: key

  @doc """
  Returns a list of unique keywords from a list of keywords while
  preserving the order of the first occurrence of each keyword.

  ## Example

      iex> AshPagify.Misc.unique_keywords([:a, :b, :a, :c, :b])
      [:a, :b, :c]

      iex> AshPagify.Misc.unique_keywords([a: 1, b: 2, a: 3, c: 4, b: 5])
      [a: 1, b: 2, c: 4]
  """
  def unique_keywords(keyword_list) when is_list(keyword_list) do
    unique_keywords(keyword_list, %{}, [])
  end

  defp unique_keywords([], _seen, result) do
    Enum.reverse(result)
  end

  defp unique_keywords([{key, value} | rest], seen, result) do
    case Map.get(seen, key) do
      nil ->
        unique_keywords(rest, Map.put(seen, key, value), [{key, value} | result])

      _ ->
        unique_keywords(rest, seen, result)
    end
  end

  defp unique_keywords([keyword | rest], seen, result) do
    case Map.get(seen, keyword) do
      nil ->
        unique_keywords(rest, Map.put(seen, keyword, true), [keyword | result])

      _ ->
        unique_keywords(rest, seen, result)
    end
  end

  @doc """
  Remove nil values from a map or struct. Does not work with nested maps.

  ## Example

      iex> AshPagify.Misc.remove_nil_values(%{a: 1, b: nil, c: 3})
      %{a: 1, c: 3}

      iex> AshPagify.Misc.remove_nil_values(%{a: 1, b: %{c: nil, d: 4}})
      %{a: 1, b: %{c: nil, d: 4}}
  """
  def remove_nil_values(map_or_struct)
  def remove_nil_values(nil), do: nil

  def remove_nil_values(struct) when is_atom(struct) do
    struct
    |> Map.from_struct()
    |> remove_nil_values()
  end

  def remove_nil_values(%{} = map) do
    map
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Coerce a maybe empty map to nil if it is empty.

  ## Example

      iex> AshPagify.Misc.coerce_maybe_empty_map(%{})
      nil

      iex> AshPagify.Misc.coerce_maybe_empty_map(%{a: 1})
      %{a: 1}

      iex> AshPagify.Misc.coerce_maybe_empty_map(nil)
      nil
  """
  @spec coerce_maybe_empty_map(any()) :: map() | nil
  def coerce_maybe_empty_map(maybe_empty_map) when is_map(maybe_empty_map) do
    if Enum.empty?(maybe_empty_map) do
      nil
    else
      maybe_empty_map
    end
  end

  def coerce_maybe_empty_map(map), do: map

  @doc """
  Puts a `value` under `key` only if the value is not `nil`, `[]`, `""`, or `%{}`.

  If a `:default` value is passed, it only puts the value into the list if the
  value does not match the default value.

      iex> maybe_put([], :a, "b")
      [a: "b"]

      iex> maybe_put([], :a, nil)
      []

      iex> maybe_put([], :a, [])
      []

      iex> maybe_put([], :a, %{})
      []

      iex> maybe_put([], :a, "")
      []

      iex> maybe_put([], :a, "a", "a")
      []

      iex> maybe_put([], :a, "a", "b")
      [a: "a"]
  """
  @spec maybe_put(Keyword.t(), atom(), any(), any()) :: keyword
  def maybe_put(params, key, value, default \\ nil)
  def maybe_put(keywords, _, nil, _), do: keywords
  def maybe_put(keywords, _, [], _), do: keywords
  def maybe_put(keywords, _, map, _) when map == %{}, do: keywords
  def maybe_put(keywords, _, "", _), do: keywords
  def maybe_put(keywords, _, val, val), do: keywords
  def maybe_put(keywords, key, value, _), do: Keyword.put(keywords, key, value)

  @doc """
  Puts the scopes params of a AshPagify struct into a keyword list only if they don't
  match the defaults either passed as last argument or loaded on the fly.

  Example:

      iex> maybe_put_scopes([], %AshPagify{scopes: %{status: :inactive}}, default_scopes: %{status: :active})
      [scopes: %{status: :inactive}]

      iex> maybe_put_scopes([], %AshPagify{scopes: %{status: :active}}, default_scopes: %{status: :active})
      []

      iex> alias AshPagify.Factory.Post
      iex> maybe_put_scopes([], %AshPagify{scopes: %{status: :active}}, for: Post)
      [scopes: %{status: :active}]
  """
  @spec maybe_put_scopes(Keyword.t(), AshPagify.t(), Keyword.t()) :: Keyword.t()
  def maybe_put_scopes(keywords, ash_pagify, opts \\ [])

  def maybe_put_scopes(keywords, ash_pagify, opts) do
    default_scopes = maybe_load_default_scopes(opts)
    scopes = ash_pagify.scopes || %{}

    scopes =
      scopes
      |> Enum.reduce(%{}, fn {group, name}, acc ->
        if default_scope?(group, name, default_scopes) do
          acc
        else
          Map.put(acc, group, name)
        end
      end)
      |> coerce_maybe_empty_map()

    maybe_put(keywords, :scopes, scopes)
  end

  defp maybe_load_default_scopes(opts) do
    if Keyword.has_key?(opts, :default_scopes) do
      Keyword.get(opts, :default_scopes, %{})
    else
      resource = Keyword.get(opts, :for)
      opts = maybe_put_compiled_scopes(resource, opts)
      Keyword.get(opts, :__compiled_default_scopes, %{})
    end
  end

  defp default_scope?(_, _, nil), do: false

  defp default_scope?(group, name, default_scopes) do
    Map.get(default_scopes, group) == name
  end

  @doc """
  Put compiled ash_pagify scopes into the options if they are not already there.

  ## Example

      iex> alias AshPagify.Factory.Post
      iex> AshPagify.Misc.maybe_put_compiled_scopes(Post)
      [
        __compiled_default_scopes: %{status: :all},
        __compiled_scopes: %{
          role: [
            %{name: :admin, filter: %{author: "John"}},
            %{name: :user, filter: %{author: "Doe"}}
          ],
          status: [
            %{name: :all, filter: nil, default?: true},
            %{name: :active, filter: %{age: %{lt: 10}}},
            %{name: :inactive, filter: %{age: %{gte: 10}}}
          ]
        }
      ]

  Or with default scopes passed as opts

      iex> alias AshPagify.Factory.Post
      iex> scopes = %{role: [%{name: :user, filter: %{author: "Doe"}, default?: true}]}
      iex> AshPagify.Misc.maybe_put_compiled_scopes(Post, [scopes: scopes])
      [
        __compiled_default_scopes: %{role: :user, status: :all},
        __compiled_scopes: %{
          role: [
            %{name: :admin, filter: %{author: "John"}},
            %{name: :user, filter: %{author: "Doe"}, default?: true}
          ],
          status: [
            %{name: :all, filter: nil, default?: true},
            %{name: :active, filter: %{age: %{lt: 10}}},
            %{name: :inactive, filter: %{age: %{gte: 10}}}
          ]
        },
        scopes: scopes
      ]
  """
  @spec maybe_put_compiled_scopes(Ash.Query.t() | Ash.Resource.t(), Keyword.t()) ::
          Keyword.t()
  def maybe_put_compiled_scopes(query_or_resource, opts \\ [])

  def maybe_put_compiled_scopes(%Ash.Query{resource: resource}, opts) do
    maybe_put_compiled_scopes(resource, opts)
  end

  def maybe_put_compiled_scopes(resource, opts) do
    if scopes_compiled?(opts) do
      opts
    else
      scopes = get_option(:scopes, Keyword.put(opts, :for, resource))

      opts
      |> Keyword.put(:__compiled_scopes, scopes)
      |> Keyword.put(:__compiled_default_scopes, default_scopes(scopes))
    end
  end

  defp scopes_compiled?(opts) do
    Keyword.has_key?(opts, :__compiled_scopes)
  end

  defp default_scopes(scopes) do
    scopes
    |> Enum.reduce(%{}, fn {group, scopes}, acc ->
      Enum.reduce(scopes, acc, fn scope, acc -> maybe_put_default_scope(acc, group, scope) end)
    end)
    |> coerce_maybe_empty_map()
  end

  defp maybe_put_default_scope(scopes, group, scope) do
    if Map.get(scope, :default?) do
      Map.put(scopes, group, scope.name)
    else
      scopes
    end
  end
end
