defmodule AshPagify.Meta do
  @moduledoc """
  Defines a struct for holding meta information of a query result.
  """

  alias AshPagify.Meta
  alias AshPagify.Misc

  defstruct current_limit: nil,
            current_offset: nil,
            current_page: nil,
            current_search: nil,
            default_scopes: nil,
            errors: [],
            has_next_page?: false,
            has_previous_page?: false,
            next_offset: nil,
            opts: [],
            ash_pagify: %AshPagify{},
            params: %{},
            previous_offset: nil,
            resource: nil,
            total_count: nil,
            total_pages: nil

  @typedoc """
  Meta information for a query result.

  - `:current_limit` - The `:limit` value used in the query
  - `:current_offset` - The `:offset` value used in the query
  - `:current_page` - A derived value when using offset-based pagination. Note that
    the value will be rounded if the offset lies between pages.
  - `:current_search` - The current full-text search term.
  - `:default_scopes` - Default scopes loaded for this resource and query.
  - `:errors` - Any validation errors that occurred.
  - `:has_previous_page?`, `:has_next_page?` - Whether there are previous or next
    pages based on the current page and total pages.
  - `:previous_offset`, `:next_offset` - Values based on `:current_page`
    and `:current_offset`/`current_limit`.
  - `:opts` - The options passed to the `AshPagify` struct.
  - `:ash_pagify` - The `AshPagify` struct used in the query.
  - `:params` - The original, unvalidated params that were passed. Only set
    if validation errors occurred.
  - `:resource` - The `Ash.Resource` that was queried.
  - `:total_count` - The total count of records for the given query.
  - `:total_pages` - The total page count based on the total record count and the limit.
  """
  @type t :: %__MODULE__{
          current_limit: pos_integer() | nil,
          current_offset: non_neg_integer() | nil,
          current_page: pos_integer() | nil,
          current_search: String.t() | nil,
          default_scopes: map() | nil,
          errors: [{atom(), term()}] | nil,
          has_next_page?: boolean(),
          has_previous_page?: boolean(),
          next_offset: non_neg_integer() | nil,
          opts: Keyword.t(),
          ash_pagify: AshPagify.t(),
          params: %{optional(String.t()) => term()},
          previous_offset: non_neg_integer() | nil,
          resource: Ash.Resource.t() | nil,
          total_count: non_neg_integer() | nil,
          total_pages: non_neg_integer() | nil
        }

  @doc """
  Returns a `AshPagify.Meta` struct with the given params, errors, and opts.

  This function is used internally to build error responses in case of
  validation errors. You can use it to add additional parameter validation.

  ## Example

  In this list function, the given parameters are first validated with
  `AshPagify.validate/2`, which returns a `AshPagify` struct on success. You can then pass
  that struct to a custom validation function, along with the original
  parameters and the opts, which both are needed to call this function.

      def list_posts(%{} = params) do
        opts = []

        with {:ok, %AshPagify{} = ash_pagify} <- AshPagify.validate(Post, params, opts),
             {:ok, %AshPagify{} = ash_pagify} <- custom_validation(ash_pagify, params, opts) do
          AshPagify.run(Post, ash_pagify, opts)
        end
      end

  In your custom validation function, you can retrieve and manipulate the filter
  values in the `AshPagify` struct.

      defp custom_validation(%AshPagify{} = ash_pagify, %{} = params, opts) do
        filters = ash_pagify.filters

        if Keyword.get(filters, :name) != nil do
          errors = [filters: [%Ash.Error.Query.InvalidFilterReference{field: :name}]]
          {:error, AshPagify.Meta.with_errors(params, errors, opts)}
        else
          {:ok, ash_pagify}
        end
      end
  """
  def with_errors(%{} = params, errors, opts) when is_list(errors) and is_list(opts) do
    %__MODULE__{
      errors: errors,
      opts: opts,
      params: params
    }
  end

  @doc """
  Updates the filter form of a AshPagify.Meta struct.

  If the filter already exists, it will be replaced with the new value. If the
  filter does not exist, it will be added to the filter form map.

  If the reset option is set to false, the offset will not be reset to 0.

  ## Examples
      iex>  set_filter_form(%AshPagify.Meta{}, %{"field" => "name", "operator" => "eq", "value" => "Post 2"})
      %AshPagify.Meta{ash_pagify: %AshPagify{filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 2"}}}

      iex> set_filter_form(%AshPagify.Meta{ash_pagify: %AshPagify{filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"}}}, %{"field" => "name", "operator" => "eq", "value" => "Post 2"})
      %AshPagify.Meta{ash_pagify: %AshPagify{filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 2"}}}

      iex> set_filter_form(%AshPagify.Meta{ash_pagify: %AshPagify{filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"}}}, %{"negated" => false, "operator" => "and"})
      %AshPagify.Meta{ash_pagify: %AshPagify{filter_form: nil}}
  """
  @spec set_filter_form(Meta.t(), map(), Keyword.t()) :: Meta.t()
  def set_filter_form(meta, filter_form, opts \\ [])

  def set_filter_form(%Meta{ash_pagify: ash_pagify} = meta, filter_form, opts)
      when filter_form == %{"negated" => false, "operator" => "and"} do
    ash_pagify = maybe_reset_offset(%{ash_pagify | filter_form: nil}, opts)
    %{meta | ash_pagify: ash_pagify}
  end

  def set_filter_form(%Meta{ash_pagify: ash_pagify} = meta, filter_form, opts) do
    ash_pagify = maybe_reset_offset(%{ash_pagify | filter_form: filter_form}, opts)
    %{meta | ash_pagify: ash_pagify}
  end

  defp maybe_reset_offset(%AshPagify{} = ash_pagify, opts) do
    reset_on_filter = Misc.get_option(:reset_on_filter?, opts, true)

    if reset_on_filter do
      %{ash_pagify | offset: nil}
    else
      ash_pagify
    end
  end
end
