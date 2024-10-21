![Elixir CI](https://github.com/zebbra/ash_pagify/workflows/AshPagify%20CI/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Hex version badge](https://img.shields.io/hexpm/v/ash_pagify.svg)](https://hex.pm/packages/ash_pagify)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/ash_pagify)

# AshPagify

<!-- MDOC -->

AshPagify is an Elixir library designed to easily add full-text search, scoping, filtering,
ordering, and pagination APIs for the [Ash Framework](https://hexdocs.pm/ash).

It takes concepts from `Flop`, `Flop.Phoenix`, `Ash` and `AshPhoenix.FilterForm` and
combines them into a single library.

It's main purpose is to provide functions to convert user input for full-text search, scoping,
filtering, ordering, and pagination into the following data structures:

1. `AshPagify.Meta` a struct holding information of a db query result.
2. query parameters for url building and to restore the query parameters from the url.
3. a basic map syntax which for example can be stored in a session or database (and restore
  the information from it).

Further, it provides headless components to build sortable tables and pagination links in your
Phoenix LiveView with the `AshPagify.Components` module. Finally, it provides a simple way to build
filter forms for your LiveView with the `AshPagify.FilterForm` struct.

## Examples

```elixir
ash_pagify = %AshPagify{
  search: "Post 1",
  scopes: %{role: :admin},
  filters: %{"comments_count" => %{"gt" => 2}},
  filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"},
  order_by: :name,
  limit: 10,
  offset: 0
}
opts = [full_text_search: [tsvector: :custom_tsvector]]

AshPagify.query_to_filters_map(Post, ash_pagify, opts).filters
%{
  "__full_text_search" => %{
    "search" => "Post 1",
    "tsvector" => "custom_tsvector"
  },
  "and" => [
    %{"comments_count" => %{"gt" => 2}},
    %{"name" => %{"eq" => "Post 1"}},
    %{"author" => "John"}
  ]
}

AshPagify.Components.build_path("/posts", ash_pagify, opts)
"/posts?search=Post+1&limit=10&scopes[role]=admin&filter_form[field]=name&filter_form[operator]=eq&filter_form[value]=Post+1&order_by[]=name"
```

## Features

- **Full-text search**: AshPagify supports full-text search using the `tsvector` column in PostgreSQL.
- **Offset-based pagination**: AshPagify uses `OFFSET` and `LIMIT` to paginate your queries.
- **Scoping**: Apply predefined filters to your queries using a simple map syntax.
- **Filtering**: Apply user-input filters to your queries using a simple map syntax. Allows complex data filtering using multiple conditions, operators, and fields. Also incooperates with `AshPhoenix.FilterForm` to provide a simple way to build complex filter user interfaces.
- **Sorting**: Sort your queries by multiple fields and any directions.
- **UI helpers and URL builders**: AshPagify provides a `AshPagify.Meta` struct with information about the current page, total pages, and more. This information can be used to build pagination links in your UI. Further, `AshPagify` provides the `AshPagify.Components` module with headless table and pagination components to easily build sortable tables and pagination links in your Phoenix LiveView. The `AshPagify.FilterForm` module provides a simple way to build filter forms for your LiveView.

## Overview

- [Examples](#examples)
- [Features](#features)
- [Installation](#installation)
- [Global configuration](#global-configuration)
- [Resource configuration](#resource-configuration)
- [LiveView configuration](#liveview-configuration)
  - [LiveView streams](#liveview-streams)
  - [Replace invalid params](#replace-invalid-params)
  - [Custom read action](#custom-read-action)
- [Full-text search](#full-text-search)
- [Sortable tables and pagination](#sortable-tables-and-pagination)
- [Parameter format](#parameter-format)
  - [Search query](#search-query)
  - [Pagination](#pagination)
  - [Scoping](#scoping)
  - [Filter forms](#filter-forms)
  - [Ordering](#ordering)
  - [Internal parameters](#internal-parameters)
- [Release Management](#release-management)

## Installation

AshPagify requires the following dependencies to be installed:

- `Ash` - The main library for building queries.
- `ash_phoenix` - The Phoenix integration for Ash.
- `AshPostgres` - The PostgreSQL integration for Ash.
- `AshUUID` - The UUID integration for Ash.
- `Phoenix` - The Phoenix web framework.

Then simply add `ash_pagify` to your list of dependencies in `mix.exs` and run
`mix deps.get`:

```elixir
def deps do
  [
    {:ash_pagify, "~> 1.1.0"}
  ]
end
```

## Global configuration

You can set some global options like the default_limit via the application
environment. All global options can be overridden by setting them
on the resource itself or by passing them directly to the functions.

```elixir
config :ash_pagify,
  default_limit: 50,
  max_limit: 1000,
  scopes: %{
    role: [
      %{name: :all, filter: nil},
      %{name: :admin, filter: %{role: "admin"}},
      %{name: :user, filter: %{role: "user"}}
    ]
  },
  full_text_search: [
    negation: true,
    prefix: true,
    any_word: false
  ],
  reset_on_filter?: true,
  replace_invalid_params?: true,
  table: [],
  pagination: []
```

See `t:AshPagify.option/0` for a description of all available options.

## Resource configuration

All settings described in the global configuration can be overridden in the resource
module. For this, you need to define the `@ash_pagify_options` module attribute (and
it's corresponding function to expose the configuration) and set the options you want
to override.

Also, you need to add the `pagination macro` call to the action of the resource that you
want to be paginated. The macro call is used to set the default limit, offset and
other options for the pagination.

```elixir
defmodule YourApp.Resource.Post
  # only required if you want to implement full-text search
  use AshPagify.Tsearch
  require Ash.Expr

  @ash_pagify_options {
    default_limit: 15,
    scopes: [
      role: [
        %{name: :all, filter: nil},
        %{name: :admin, filter: %{author: "John"}},
        %{name: :user, filter: %{author: "Doe"}}
      ]
    ]
  }
  def ash_pagify_options, do: @ash_pagify_options

  actions do
    read :read do
      #...
      pagination offset?: true,
                default_limit: @ash_pagify_options.default_limit,
                countable: true,
                required?: false
    end
  end

  calculations do
    # provide your default `tsvector` calculation for full-text search
    calculate :tsvector,
              AshPostgres.Tsvector,
              expr(
                fragment(
                  "to_tsvector('simple', coalesce(?, '')) || to_tsvector('simple', coalesce(?, ''))",
                  name,
                  title
                )
              ),
              public?: true
  end
  #...
end
```

## LiveView configuration

In your LiveView, fetch the data and assign it alongside the meta data to the socket.

```elixir
defmodule YourAppWeb.PostLive.IndexLive do
  use YourAppWeb, :live_view

  alias YourApp.Resource.Post

  @impl true
  def handle_params(params, _, socket) do
    case Post.list_posts(params) do
      {:ok, {posts, meta}} ->
        {:noreply, assign(socket, %{posts: posts, meta: meta})}
      {:error, _meta} ->
        # This will reset invalid parameters. Alternatively, you can assign
        # only the meta and render the errors, or assign the validated params,
        # or you can ignore the error case entirely.
        {:noreply, push_navigate(socket, to: ~p"/posts")}
    end
  end

  defp list_posts(params, opts \\ []) do
    AshPagify.validate_and_run(Post, params, opts)
  end
end
```

### LiveView streams

To use LiveView streams, you can change your `handle_params/3` function as follows:

```elixir
def handle_params(params, _, socket) do
  case Post.list_posts(params) do
    {:noreply,
        socket
        |> assign(:meta, meta)
        |> stream(:posts, posts, reset: true)}
  # ...
  end
end
```

### Replace invalid params

To replace invalid ash_pagify parameters with their default values, you can use the `replace_invalid_params?` option. You can change your `handle_params/3` function as follows:

```elixir
def handle_params(params, _, socket) do
  case Post.list_posts(params, replace_invalid_params?: true) do
      {:ok, {posts, meta}} ->
        {:noreply, assign(socket, %{posts: posts, meta: meta})}
      {:error, meta} ->
        valid_path = AshPagify.Components.build_path(~p"/posts", meta.params)
        {:noreply, push_navigate(socket, to: valid_path)}
  # ...
  end
end
```

### Custom read action

If the `:action` option is set (to perform a custom read action), the fourth argument
`args` will be passed to the action as arguments.

```elixir
%Ash.Page.Offset{count: count} = AshPagify.all(Comment, %AshPagify{}, [action: :by_post], post.id)
```

## Full-text search

We allow full-text search using the `tsvector` column in PostgreSQL. To enable full-text search,
you need to either `use AshPagify.Tsearch` in your module or implement the `full_text_search`,
`full_text_search_rank`, `tsquery`, and `tsvector` calculations as described in `AshPagify.Tsearch`
(tsvector calculation  is always mandatory).

```elixir
# provide the default tsvector calculation for full-text search
calculate :tsvector,
          AshPostgres.Tsvector,
          expr(
            fragment(
              "to_tsvector('simple', coalesce(?, '')) || to_tsvector('simple', coalesce(?, ''))",
              name,
              title
            )
          ),
          public?: true
```

Or if you want to use a generated tsvector column, you can replace the fields
part with the name of your generated tsvector column:

```elixir
# use a tsvector column from the database
calculate :tsvector, AshPostgres.Tsvector, expr(tsv), public?: true
```

You can also configure `dynamic` tsvectors based on user input. Have a look at the
`AshPagify.Tsearch` module for more information.

Once configured, you can use the `search` parameter to apply full-text search.

## Sortable tables and pagination

To add a sortable table and pagination links, you can add the following to your template:

```elixir
<h1>Posts</h1>

<AshPagify.Components.table items={@posts} meta={@meta} path={~p"/posts"}>
  <:col :let={post} label="Name" field={:name}><%= post.name %></:col>
  <:col :let={post} label="Author" field={:author}><%= post.author %></:col>
</AshPagify.Components.table>

<AshPagify.Components.pagination meta={@meta} path={~p"/posts"} />
```

In this context, path points to the current route, and AshPagify Components appends
full-text search, pagination, scoping, filtering, and sorting parameters to it.
You can use verified routes, route helpers, or custom path builder functions.
You'll find explanations for the different formats in the documentation for
`AshPagify.Components.build_path/3`.

Note that the field attribute in the `:col` slot is optional. If set and the
corresponding field in the resource is defined as sortable, the table header for
that column will be interactive, allowing users to sort by that column. However,
if the field isn't defined as sortable, or if the field attribute is omitted, or
set to `nil` or `false`, the table header will not be clickable.

You also have the option to pass a `Phoenix.LiveView.JS` command instead of or
in addition to a path. For more details, please refer to the component
documentation.

## Parameter format

The AshPagify library requires parameters to be provided in a specific format as a map.
This map can be translated into a URL query parameter string, typically for use in a
web framework like Phoenix.

The following parameters are encoded as strings and handled by the library:

- `search` - A string to search for in the full-text search column or in the searchable fields.
- `limit` - The number of records to return.
- `offset` - The number of records to skip.
- `scopes` - A map of predefined filters to apply to the query.
- `filter_form` - A map of filters provided by the `AshPagify.FilterForm` module.
- `order_by` - A list of fields to order by.

## Search query

You can search for a string in a full-text search column.

```elixir
%{search: "John"}
```

This translates to the following query parameter string:

```URL
?search=John
```

You can use the `AshPagify.set_search/3` function to set the search query in the
`AshPagify` struct.

```elixir
ash_pagify = AshPagify.set_search(%AshPagify{}, "John")
```

## Pagination

You can specify an offset to start from and a limit to the number of results.

```elixir
%{offset: 100, limit: 20}
```

This translates to the following query parameter string:

```URL
?offset=100&limit=20
```

You can use the `AshPagify.set_offset/2` and `AshPagify.set_limit/3` functions to set
the offset and limit in the `AshPagify` struct.

```elixir
ash_pagify = AshPagify.set_offset(%AshPagify{}, 100)
ash_pagify = AshPagify.set_limit(ash_pagify, 20)
```

## Scoping

To apply predefined filters to a query, you can set the `:scopes` parameter. `:scopes`
should be a map of predefined filters (maps) available in your resource. The filter name
is used to look up the predefined filter. If the filter is found, it is applied to
the query. If the filter is not found, an error is raised.

```elixir
%{scopes: %{role: :admin}}
```

This translates to the following query parameter string:

```URL
?scopes[role]=admin
```

You can use the `AshPagify.set_scope/3` function to set the scopes in the `AshPagify` struct.

```elixir
ash_pagify = AshPagify.set_scope(%AshPagify{}, %{role: :admin})
```

## Filter forms

Filter forms can be passed as a map of filter conditions. Usually, this map is generated
by a filter form component using the `AshPagify.FilterForm` module. `AshPagify.FilterForm.params_for_query/2`
can be used to convert the form filter map into a query map.

```elixir
%{filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"}}
```

This translates to the following query parameter string:

```URL
?filter_form[name][eq]=Post%201
```

You can use the `AshPagify.set_filter_form/3` function to set the filter form in the `AshPagify` struct.

```elixir
ash_pagify = AshPagify.set_filter_form(%AshPagify{}, %{"field" => "name", "operator" => "eq", "value" => "Post 1"})
```

Check the `AshPhoenix.FilterForm` documentation for more information.
See `Ash.Query.filter/2` for a list of all available filter operators.

## Ordering

To add an ordering clause to a query, you need to set the `:order_by`
parameter. `:order_by` should be a list of fields, aggregates, or calculations
available in your resource. The order direction can be set by adding
one of the following prefixes to the field name:

- `""` or `+` for ascending order
- `-` for descending order
- `++` for ascending order with nulls first
- `--` for descending order with nulls last

If no order directions are given, `:asc` is used as default.

```elixir
%{order_by: ["name", "--author"]}
```

This translates to the following query parameter string:

```URL
?order_by=[]name&oder_by[]=--author
```

You can use the `AshPagify.push_order/3` function to set the order by clause in the `AshPagify` struct.

```elixir
ash_pagify = AshPagify.push_order(%AshPagify{}, "name")
```

## Internal parameters

AshPagify is designed to manage parameters that come from the user side. While it is
possible to alter those parameters and append extra filters upon receiving them,
it is advisable to clearly differentiate parameters coming from outside and the
parameters that your application adds internally.

Consider the scenario where you need to scope a query based on the current user.
In this case, it is better to create a separate function that introduces the
necessary filter clauses:

```elixir
def list_posts(%{} = params, %User{} = current_user) do
  Post
  |> scope(current_user)
  |> AshPagify.validate_and_run(params)
end

defp scope(query, %User{role: :admin}), do: query
defp scope(query, %User{id: user_id}), do: Ash.Query.filter_input(query, %{user_id: ^user_id})
```

If you need to add extra filters that are only used internally and aren't exposed to the user,
you can pass them as a separate argument. This same argument can be used to override certain
options depending on the context in which the function is called.

```elixir
def list_posts(%{} = params, opts \\\\ [], %User{} = current_user) do
  ash_pagify_opts =
    opts
    |> Keyword.put(:max_limit, 10)
    |> Keyword.put(:default_limit, 10)
    |> Keyword.put(:replace_invalid_params?, true)

  Post
  |> scope(current_user)
  |> apply_filters(opts)
  |> AshPagify.validate_and_run(params, ash_pagify_opts)
end

defp scope(query, %User{role: :admin}), do: query
defp scope(query, %User{id: user_id}), do: Ash.Query.filter_input(query, %{user_id: ^user_id})

defp apply_filters(query, opts) do
  Enum.reduce(opts, query, fn
    {:updated_at, dt}, query -> Ash.Query.filter_input(query, %{updated_at: dt})
    _, query -> query
  end)
end
```

With this approach, you maintain a clean separation between user-driven parameters and
system-driven parameters, leading to more maintainable and less error-prone code. Please be
aware that in most cases it is better to use `Ash.Policy` to manage access control. This
example is just to illustrate the concept.

Under the hood, the `AshPagify.validate_and_run/4` or `AshPagify.validate_and_run!/4` functions
just call `AshPagify.validate/2` and `AshPagify.run/4`, which in turn calls `AshPagify.all/4` and
`AshPagify.meta/3`.

See `AshPagify.Meta` for descriptions of the meta fields.

Alternatively, you may separate parameter validation and data fetching into different
steps using the `AshPagify.validate/2`, `AshPagify.validate!/2`, and `AshPagify.run/4` functions.
This allows you to manipulate the validated parameters, to modify the query depending on
the parameters, or to move the parameter validation to a different layer of your application.

```elixir
with {:ok, ash_pagify} <- AshPagify.validate(Post, params) do
  {:ok, {results, meta}} = AshPagify.run(Post, ash_pagify)
end
```

The aforementioned functions internally call the lower-level functions `AshPagify.all/4` and
`AshPagify.meta/3`. If you have advanced requirements, you might prefer to use these functions
directly. However, it's important to note that these lower-level functions do not validate
the parameters. If parameters are generated based on user input, they should always be
validated first using `AshPagify.validate/2` or `AshPagify.validate!/2` to ensure safe execution.

## Release Management

We use [git_opts](https://hexdocs.pm/git_ops/readme.html) to manage our releases. To create a new release, run:

```bash
mix git_ops.release
```

This will bump the version, create a new tag, and push the changes to the repository. The GitHub action will then build and publish the new version to Hex.
