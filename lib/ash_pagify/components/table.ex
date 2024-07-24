defmodule AshPagify.Components.Table do
  @moduledoc """
  Table component for AshPagify.
  """

  use Phoenix.Component

  alias AshPagify.Components
  alias AshPagify.Meta
  alias AshPagify.Misc
  alias Phoenix.LiveView.JS

  @spec default_opts() :: [Components.table_option()]
  def default_opts do
    [
      container: false,
      container_attrs: [class: "table-container"],
      no_results_content: Phoenix.HTML.raw("<p>No results.</p>"),
      symbol_asc: "▴",
      symbol_attrs: [class: "order-direction"],
      symbol_desc: "▾",
      symbol_unsorted: nil,
      table_attrs: [],
      tbody_attrs: [],
      tbody_td_attrs: [],
      tbody_tr_attrs: [],
      thead_attrs: [],
      th_wrapper_attrs: [],
      thead_th_attrs: [],
      thead_tr_attrs: [],
      limit_order_by: nil
    ]
  end

  def merge_opts(opts) do
    default_opts()
    |> Misc.list_merge(Misc.get_global_opts(:table))
    |> Misc.list_merge(opts)
  end

  attr :id, :string, required: true
  attr :meta, Meta, required: true
  attr :path, :any, required: true
  attr :on_sort, JS
  attr :target, :string, required: true
  attr :caption_text, :string, required: true
  attr :caption, :any
  attr :opts, :any, required: true
  attr :col, :any
  attr :items, :list, required: true
  attr :foot, :any, required: true
  attr :row_id, :any, default: nil
  attr :row_click, JS, default: nil
  attr :row_item, :any, required: true
  attr :action, :any, required: true

  def render(assigns) do
    assigns =
      with %{items: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table id={@id} {@opts[:table_attrs]}>
      <caption :if={@caption_text}><%= @caption_text %></caption>
      <caption :for={caption <- @caption}>
        <%= render_slot(caption) %>
      </caption>
      <.maybe_colgroup col={@col ++ @action} />
      <thead {@opts[:thead_attrs]}>
        <tr {@opts[:thead_tr_attrs]}>
          <.header_column
            :for={col <- @col}
            :if={show_column?(col)}
            on_sort={@on_sort}
            field={col[:field]}
            label={col[:label]}
            sortable={sortable?(col[:field], @meta.resource)}
            directions={col[:directions]}
            meta={@meta}
            thead_th_attrs={merge_attrs(@opts[:thead_th_attrs], col, :thead_th_attrs)}
            symbol_asc={@opts[:symbol_asc]}
            symbol_desc={@opts[:symbol_desc]}
            symbol_unsorted={@opts[:symbol_unsorted]}
            symbol_attrs={@opts[:symbol_attrs]}
            th_wrapper_attrs={merge_attrs(@opts[:th_wrapper_attrs], col, :th_wrapper_attrs)}
            path={@path}
            target={@target}
            limit_order_by={@opts[:limit_order_by]}
          />
          <.header_column
            :for={action <- @action}
            :if={show_column?(action)}
            field={nil}
            label={action[:label]}
            sortable={false}
            meta={@meta}
            thead_th_attrs={merge_attrs(@opts[:thead_th_attrs], action, :thead_th_attrs)}
            path={nil}
            target={@target}
          />
        </tr>
      </thead>
      <tbody
        id={@id <> "_tbody"}
        phx-update={match?(%Phoenix.LiveView.LiveStream{}, @items) && "stream"}
        {@opts[:tbody_attrs]}
      >
        <tr
          :for={item <- @items}
          id={@row_id && @row_id.(item)}
          {maybe_invoke_options_callback(@opts[:tbody_tr_attrs], item, assigns)}
        >
          <td
            :for={col <- @col}
            :if={show_column?(col)}
            {merge_td_attrs(@opts[:tbody_td_attrs], col, item)}
            phx-click={@row_click && @row_click.(item)}
          >
            <%= render_slot(col, @row_item.(item)) %>
          </td>
          <td :for={action <- @action} {merge_td_attrs(@opts[:tbody_td_attrs], action, item)}>
            <%= render_slot(action, @row_item.(item)) %>
          </td>
        </tr>
      </tbody>
      <tfoot :if={@foot != []}><%= render_slot(@foot) %></tfoot>
    </table>
    """
  end

  defp merge_attrs(base_attrs, col, key) when is_atom(key) do
    attrs = Map.get(col, key, [])
    merged_attrs = Keyword.merge(base_attrs, attrs)
    maybe_merge_custom_class(merged_attrs, col, key)
  end

  defp merge_td_attrs(tbody_td_attrs, col, item) do
    attrs =
      col |> Map.get(:tbody_td_attrs, []) |> maybe_invoke_options_callback(item, %{})

    attrs = Keyword.merge(tbody_td_attrs, attrs)
    maybe_merge_custom_class(attrs, col, :tbody_td_attrs)
  end

  defp maybe_invoke_options_callback(option, item, assigns) when is_function(option) do
    option.(item, assigns)
  end

  defp maybe_invoke_options_callback(option, _item, _assigns), do: option

  defp maybe_merge_custom_class(attrs, %{class: class}, key) when key == :thead_th_attrs or key == :tbody_td_attrs do
    base_class = Keyword.get(attrs, :class, "")
    Keyword.put(attrs, :class, "#{base_class} #{class}")
  end

  defp maybe_merge_custom_class(attrs, _, _), do: attrs

  defp maybe_colgroup(assigns) do
    ~H"""
    <colgroup :if={Enum.any?(@col, &(&1[:col_style] || &1[:col_class]))}>
      <col
        :for={col <- @col}
        :if={show_column?(col)}
        {reject_empty_values(style: col[:col_style], class: col[:col_class])}
      />
    </colgroup>
    """
  end

  defp reject_empty_values(attrs) do
    Enum.reject(attrs, fn {_, v} -> v in ["", nil] end)
  end

  defp show_column?(%{hide: true}), do: false
  defp show_column?(%{show: false}), do: false
  defp show_column?(_), do: true

  attr :meta, Meta, required: true
  attr :field, :atom, required: true
  attr :label, :any, required: true
  attr :path, :any, required: true
  attr :on_sort, JS
  attr :target, :string, required: true
  attr :sortable, :boolean, required: true
  attr :thead_th_attrs, :list, required: true
  attr :class, :string
  attr :directions, :any
  attr :symbol_asc, :any
  attr :symbol_desc, :any
  attr :symbol_unsorted, :any
  attr :symbol_attrs, :list
  attr :th_wrapper_attrs, :list
  attr :limit_order_by, :integer, default: nil

  defp header_column(%{sortable: true} = assigns) do
    direction = order_direction(assigns.meta.ash_pagify, assigns.field)
    assigns = assign(assigns, :order_direction, direction)

    sort_path_options =
      if directions = assigns[:directions],
        do: [directions: directions],
        else: []

    limit_order_by = assigns.limit_order_by
    sort_path_options = Keyword.put(sort_path_options, :limit_order_by, limit_order_by)

    sort_path =
      build_path(
        assigns[:path],
        assigns[:meta],
        assigns[:field],
        sort_path_options
      )

    assigns = assign(assigns, :sort_path, sort_path)

    ~H"""
    <th {@thead_th_attrs} aria-sort={aria_sort(@order_direction)}>
      <span {@th_wrapper_attrs}>
        <.sort_link
          path={@sort_path}
          on_sort={@on_sort}
          field={@field}
          label={@label}
          target={@target}
        />
        <.arrow
          direction={@order_direction}
          symbol_asc={@symbol_asc}
          symbol_desc={@symbol_desc}
          symbol_unsorted={@symbol_unsorted}
          {@symbol_attrs}
        />
      </span>
    </th>
    """
  end

  defp header_column(%{sortable: false, th_wrapper_attrs: []} = assigns) do
    ~H"""
    <th {@thead_th_attrs}><%= @label %></th>
    """
  end

  defp header_column(%{sortable: false, th_wrapper_attrs: th_wrapper_attrs} = assigns) when is_list(th_wrapper_attrs) do
    ~H"""
    <th {@thead_th_attrs}>
      <span {@th_wrapper_attrs}>
        <%= @label %>
      </span>
    </th>
    """
  end

  defp header_column(%{sortable: false} = assigns) do
    ~H"""
    <th {@thead_th_attrs}><%= @label %></th>
    """
  end

  defp aria_sort(:desc), do: "descending"
  defp aria_sort(:desc_nils_last), do: "descending"
  defp aria_sort(:desc_nils_first), do: "descending"
  defp aria_sort(:asc), do: "ascending"
  defp aria_sort(:asc_nils_last), do: "ascending"
  defp aria_sort(:asc_nils_first), do: "ascending"
  defp aria_sort(_), do: nil

  attr :direction, :atom, required: true
  attr :symbol_asc, :any, required: true
  attr :symbol_desc, :any, required: true
  attr :symbol_unsorted, :any, required: true
  attr :rest, :global

  defp arrow(%{direction: direction} = assigns) when direction in [:asc, :asc_nils_first, :asc_nils_last] do
    ~H"<span {@rest}><%= @symbol_asc %></span>"
  end

  defp arrow(%{direction: direction} = assigns) when direction in [:desc, :desc_nils_first, :desc_nils_last] do
    ~H"<span {@rest}><%= @symbol_desc %></span>"
  end

  defp arrow(%{direction: nil, symbol_unsorted: nil} = assigns) do
    ~H""
  end

  defp arrow(%{direction: nil} = assigns) do
    ~H"<span {@rest}><%= @symbol_unsorted %></span>"
  end

  attr :field, :atom, required: true
  attr :label, :string, required: true
  attr :path, :string
  attr :on_sort, JS
  attr :target, :string

  defp sort_link(%{on_sort: nil, path: path} = assigns) when is_binary(path) do
    ~H"""
    <.link patch={@path}><%= @label %></.link>
    """
  end

  defp sort_link(%{} = assigns) do
    ~H"""
    <.link patch={@path} phx-click={@on_sort} phx-target={@target} phx-value-order={@field}>
      <%= @label %>
    </.link>
    """
  end

  defp order_direction(%AshPagify{order_by: [{field, direction} | _]}, field), do: direction
  defp order_direction(_ash_pagify, _field), do: nil

  defp sortable?(nil, _), do: false
  defp sortable?(_, nil), do: true

  defp sortable?(field, resoruce) do
    Ash.Resource.Info.sortable?(resoruce, field)
  end

  defp build_path(nil, _, _, _), do: nil

  defp build_path(path, meta, field, opts) do
    AshPagify.Components.build_path(
      path,
      AshPagify.push_order(meta.ash_pagify, field, opts),
      for: meta.resource,
      default_scopes: meta.default_scopes
    )
  end
end
