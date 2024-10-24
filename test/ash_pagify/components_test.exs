defmodule AshPagify.ComponentsTest do
  @moduledoc false

  use ExUnit.Case
  use Phoenix.Component

  import AshPagify.Components
  import AshPagify.Factory
  import AshPagify.TestHelpers
  import Phoenix.LiveViewTest

  alias AshPagify.Error.Components.PathOrJSError
  alias AshPagify.Factory.Post
  alias AshPagify.Meta
  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.LiveStream
  alias Plug.Conn.Query

  doctest AshPagify.Components, import: true

  @route_helper_opts [%{}, :posts]

  attr :caption_text, :string, default: nil
  attr :on_sort, JS, default: nil
  attr :id, :string, default: "some_table"
  attr :meta, Meta, default: %Meta{ash_pagify: %AshPagify{}}
  attr :opts, :list, default: [table_attrs: [class: "some-table"]]
  attr :target, :string, default: nil
  attr :loading, :boolean, default: false
  attr :error, :boolean, default: false
  attr :path, :any, default: {__MODULE__, :route_helper, @route_helper_opts}

  attr :items, :list,
    default: [
      %{name: "George", email: "george@george.post", age: 8, species: "dog"}
    ]

  defp render_table(assigns) do
    parse_heex(~H"""
    <AshPagify.Components.table
      caption_text={@caption_text}
      on_sort={@on_sort}
      id={@id}
      items={@items}
      meta={@meta}
      opts={@opts}
      path={@path}
      target={@target}
      loading={@loading}
      error={@error}
    >
      <:col :let={post} label="Name" field={:name}><%= post.name %></:col>
      <:col :let={post} label="Email" field={:email}><%= post.email %></:col>
      <:col :let={post} label="Age"><%= post.age %></:col>
      <:col :let={post} label="Species" field={:species}><%= post.species %></:col>
      <:col>column without label</:col>
    </AshPagify.Components.table>
    """)
  end

  def route_helper(%{}, action, query) do
    URI.to_string(%URI{path: "/#{action}", query: Query.encode(query)})
  end

  def path_func(params) do
    {offset, params} = Keyword.pop(params, :offset)
    query = Query.encode(params)
    if offset, do: "/posts/page/#{offset}?#{query}", else: "/posts?#{query}"
  end

  describe "pagination/1" do
    test "renders pagination wrapper" do
      assigns = %{meta: build(:meta_on_first_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} on_paginate={%JS{}} />
        """)

      nav = find_one(html, "nav:root")

      assert attribute(nav, "aria-label") == "pagination"
      assert attribute(nav, "class") == "pagination"
      assert attribute(nav, "role") == "navigation"
    end

    test "does not render anything if there is only one page" do
      assigns = %{meta: build(:meta_one_page)}

      assert parse_heex(~H"""
             <AshPagify.Components.pagination meta={@meta} on_paginate={%JS{}} />
             """) == []
    end

    test "does not render anything if there are no results" do
      assigns = %{meta: build(:meta_no_results)}

      assert parse_heex(~H"""
             <AshPagify.Components.pagination meta={@meta} on_paginate={%JS{}} />
             """) == []
    end

    test "allows to overwrite wrapper class" do
      assigns = %{meta: build(:meta_on_first_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination
          meta={@meta}
          on_paginate={%JS{}}
          opts={[wrapper_attrs: [class: "boo"]]}
        />
        """)

      nav = find_one(html, "nav:root")

      assert attribute(nav, "aria-label") == "pagination"
      assert attribute(nav, "class") == "boo"
      assert attribute(nav, "role") == "navigation"
    end

    test "allows to add attributes to wrapper" do
      assigns = %{meta: build(:meta_on_first_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination
          meta={@meta}
          on_paginate={%JS{}}
          opts={[wrapper_attrs: [title: "paginate"]]}
        />
        """)

      nav = find_one(html, "nav:root")

      assert attribute(nav, "aria-label") == "pagination"
      assert attribute(nav, "class") == "pagination"
      assert attribute(nav, "role") == "navigation"
      assert attribute(nav, "title") == "paginate"
    end

    test "renders previous link" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" />
        """)

      a = find_one(html, "a:fl-contains('Previous')")

      assert attribute(a, "class") == "pagination-previous"
      assert attribute(a, "data-phx-link") == "patch"
      assert attribute(a, "data-phx-link-state") == "push"
      assert attribute(a, "href") == "/posts?limit=10"
    end

    test "uses phx-click with on_paginate without path" do
      assigns = %{
        meta: build(:meta_on_second_page),
        on_paginate: JS.push("paginate")
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} on_paginate={@on_paginate} />
        """)

      a = find_one(html, "a:fl-contains('Previous')")

      assert attribute(a, "class") == "pagination-previous"
      assert attribute(a, "data-phx-link") == nil
      assert attribute(a, "data-phx-link-state") == nil
      assert attribute(a, "href") == "#"
      assert attribute(a, "phx-value-offset") == "0"
      assert phx_click = attribute(a, "phx-click")
      assert Jason.decode!(phx_click) == [["push", %{"event" => "paginate"}]]

      a = find_one(html, "a:fl-contains('Next')")

      assert attribute(a, "class") == "pagination-next"
      assert attribute(a, "data-phx-link") == nil
      assert attribute(a, "data-phx-link-state") == nil
      assert attribute(a, "href") == "#"
      assert attribute(a, "phx-value-offset") == "20"
      assert phx_click = attribute(a, "phx-click")
      assert Jason.decode!(phx_click) == [["push", %{"event" => "paginate"}]]
    end

    test "uses phx-click with on_paginate and path" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" on_paginate={JS.push("paginate")} />
        """)

      a = find_one(html, "a:fl-contains('Previous')")

      assert attribute(a, "class") == "pagination-previous"
      assert attribute(a, "data-phx-link") == "patch"
      assert attribute(a, "data-phx-link-state") == "push"
      assert attribute(a, "href") == "/posts?limit=10"
      assert attribute(a, "phx-value-offset") == "0"
      assert phx_click = attribute(a, "phx-click")
      assert Jason.decode!(phx_click) == [["push", %{"event" => "paginate"}]]
    end

    test "supports a function/args tuple as path" do
      assigns = %{
        meta: build(:meta_on_second_page),
        path: {&route_helper/3, @route_helper_opts}
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path={@path} />
        """)

      assert a = find_one(html, "a:fl-contains('Previous')")
      assert attribute(a, "href") == "/posts?limit=10"
    end

    test "supports a function as path" do
      assigns = %{meta: build(:meta_on_first_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path={&path_func/1} />
        """)

      assert a = find_one(html, "a:fl-contains('Next')")
      assert attribute(a, "href") == "/posts/page/10?limit=10"
    end

    test "supports a URI string as path" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" />
        """)

      assert a = find_one(html, "a:fl-contains('Previous')")
      assert attribute(a, "href") == "/posts?limit=10"
    end

    test "adds phx-target to previous link" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} on_paginate={JS.push("paginate")} target="here" />
        """)

      assert a = find_one(html, "a:fl-contains('Previous')")
      assert attribute(a, "phx-target") == "here"
    end

    test "merges query parameters into existing parameters" do
      assigns = %{
        meta: build(:meta_on_second_page),
        path: {&route_helper/3, @route_helper_opts ++ [[category: "dinosaurs"]]}
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path={@path} />
        """)

      assert previous = find_one(html, "a:fl-contains('Previous')")
      assert attribute(previous, "class") == "pagination-previous"
      assert attribute(previous, "data-phx-link") == "patch"
      assert attribute(previous, "data-phx-link-state") == "push"

      assert a = attribute(previous, "href")
      assert_urls_match(a, "/posts?category=dinosaurs&limit=10")
    end

    test "merges query parameters into existing path query parameters" do
      assigns = %{
        meta: build(:meta_on_second_page),
        path: {&route_helper/3, @route_helper_opts ++ [[category: "dinosaurs"]]}
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts?category=dinosaurs" />
        """)

      assert previous = find_one(html, "a:fl-contains('Previous')")
      assert attribute(previous, "class") == "pagination-previous"
      assert attribute(previous, "data-phx-link") == "patch"
      assert attribute(previous, "data-phx-link-state") == "push"

      assert href = attribute(previous, "href")
      assert_urls_match(href, "/posts?limit=10&category=dinosaurs")
    end

    test "allows to overwrite previous link attributes and content" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination
          meta={@meta}
          path="/posts"
          opts={[
            previous_link_attrs: [class: "prev", title: "p-p-previous"],
            previous_link_content: Phoenix.HTML.raw(~s(<i class="fas fa-chevron-left" />))
          ]}
        />
        """)

      assert link = find_one(html, "a[title='p-p-previous']")
      assert attribute(link, "class") == "prev"
      assert attribute(link, "data-phx-link") == "patch"
      assert attribute(link, "data-phx-link-state") == "push"
      assert attribute(link, "href") == "/posts?limit=10"

      assert link |> Floki.children() |> Floki.raw_html() ==
               "<i class=\"fas fa-chevron-left\"></i>"
    end

    test "disables previous link if on first page" do
      assigns = %{meta: build(:meta_on_first_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" />
        """)

      assert previous_link = find_one(html, "span:fl-contains('Previous')")
      assert attribute(previous_link, "class") == "pagination-previous disabled"
    end

    test "disables previous link if on first page when using click handlers" do
      assigns = %{meta: build(:meta_on_first_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} on_paginate={JS.push("paginate")} />
        """)

      assert previous_link = find_one(html, "span:fl-contains('Previous')")
      assert attribute(previous_link, "class") == "pagination-previous disabled"
    end

    test "allows to overwrite previous link class and content if disabled" do
      assigns = %{meta: build(:meta_on_first_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination
          meta={@meta}
          path="/posts"
          opts={[
            previous_link_attrs: [class: "prev", title: "no"],
            previous_link_content: "Previous"
          ]}
        />
        """)

      assert previous_link = find_one(html, "span:fl-contains('Previous')")

      assert attribute(previous_link, "class") == "prev disabled"
      assert attribute(previous_link, "title") == "no"
      assert text(previous_link) == "Previous"
    end

    test "renders next link" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" />
        """)

      assert link = find_one(html, "a:fl-contains('Next')")

      assert attribute(link, "class") == "pagination-next"
      assert attribute(link, "data-phx-link") == "patch"
      assert attribute(link, "data-phx-link-state") == "push"
      assert href = attribute(link, "href")
      assert_urls_match(href, "/posts?offset=20&limit=10")
    end

    test "renders next link when using click event handling" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} on_paginate={JS.push("paginate")} />
        """)

      assert link = find_one(html, "a:fl-contains('Next')")

      assert attribute(link, "class") == "pagination-next"
      assert attribute(link, "phx-value-offset") == "20"
      assert attribute(link, "href") == "#"
      assert phx_click = attribute(link, "phx-click")
      assert Jason.decode!(phx_click) == [["push", %{"event" => "paginate"}]]
    end

    test "adds phx-target to next link" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} on_paginate={JS.push("paginate")} target="here" />
        """)

      assert link = find_one(html, "a:fl-contains('Next')")
      assert attribute(link, "phx-target") == "here"
    end

    test "allows to overwrite next link attributes and content" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination
          meta={@meta}
          path="/posts"
          opts={[
            next_link_attrs: [class: "next", title: "n-n-next"],
            next_link_content: Phoenix.HTML.raw(~s("<i class="fas fa-chevron-right" />))
          ]}
        />
        """)

      assert link = find_one(html, "a[title='n-n-next']")
      assert attribute(link, "class") == "next"
      assert attribute(link, "data-phx-link") == "patch"
      assert attribute(link, "data-phx-link-state") == "push"
      assert href = attribute(link, "href")
      assert_urls_match(href, "/posts?offset=20&limit=10")

      assert attribute(link, "i", "class") == "fas fa-chevron-right"
    end

    test "disables next link if on last page" do
      assigns = %{meta: build(:meta_on_last_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" />
        """)

      assert next = find_one(html, "span:fl-contains('Next')")
      assert attribute(next, "class") == "pagination-next disabled"

      assert attribute(next, "href") == nil
    end

    test "renders next link on last page when using click event handling" do
      assigns = %{meta: build(:meta_on_last_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} on_paginate={JS.push("paginate")} />
        """)

      assert next = find_one(html, "span:fl-contains('Next')")
      assert attribute(next, "class") == "pagination-next disabled"

      assert attribute(next, "href") == nil
    end

    test "allows to overwrite next link attributes and content when disabled" do
      assigns = %{meta: build(:meta_on_last_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination
          meta={@meta}
          path="/posts"
          opts={[
            next_link_attrs: [class: "next", title: "no"],
            next_link_content: "N-n-next"
          ]}
        />
        """)

      assert next_link = find_one(html, "span:fl-contains('N-n-next')")
      assert attribute(next_link, "class") == "next disabled"
      assert attribute(next_link, "title") == "no"
    end

    test "renders page links" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" />
        """)

      assert link = find_one(html, "a[aria-label='Go to page 1']")
      assert attribute(link, "class") == "pagination-link"
      assert attribute(link, "data-phx-link") == "patch"
      assert attribute(link, "data-phx-link-state") == "push"
      assert attribute(link, "href") == "/posts?limit=10"
      assert text(link) == "1"

      assert link = find_one(html, "a[aria-label='Go to page 2']")
      assert attribute(link, "class") == "pagination-link is-current"
      assert attribute(link, "data-phx-link") == "patch"
      assert attribute(link, "data-phx-link-state") == "push"
      assert href = attribute(link, "href")
      assert_urls_match(href, "/posts?offset=10&limit=10")
      assert text(link) == "2"

      assert link = find_one(html, "a[aria-label='Go to page 3']")
      assert attribute(link, "class") == "pagination-link"
      assert attribute(link, "data-phx-link") == "patch"
      assert attribute(link, "data-phx-link-state") == "push"
      assert href = attribute(link, "href")
      assert_urls_match(href, "/posts?offset=20&limit=10")
      assert text(link) == "3"
    end

    test "renders page links when using click event handling" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} on_paginate={JS.push("paginate")} />
        """)

      assert link = find_one(html, "a[aria-label='Go to page 1']")
      assert attribute(link, "href") == "#"
      assert attribute(link, "phx-value-offset") == "0"
      assert text(link) =~ "1"
      assert phx_click = attribute(link, "phx-click")
      assert Jason.decode!(phx_click) == [["push", %{"event" => "paginate"}]]
    end

    test "adds phx-target to page link" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} on_paginate={JS.push("paginate")} target="here" />
        """)

      assert link = find_one(html, "a[aria-label='Go to page 1']")
      assert attribute(link, "phx-target") == "here"
    end

    test "doesn't render pagination links if set to hide" do
      assigns = %{meta: build(:meta_on_second_page), opts: [page_links: :hide]}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" opts={@opts} />
        """)

      assert find_one(html, "a[aria-label='Go to previous page']")
      assert Floki.find(html, "a[aria-label='Go to page 1']") == []
    end

    test "doesn't render pagination links if set to hide when passing event" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination
          meta={@meta}
          on_paginate={JS.push("paginate")}
          opts={[page_links: :hide]}
        />
        """)

      assert find_one(html, "a[aria-label='Go to previous page']")
      assert Floki.find(html, "a[aria-label='Go to page 1']") == []
    end

    test "allows to overwrite pagination link attributes" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination
          meta={@meta}
          path="/posts"
          opts={[pagination_link_attrs: [class: "p-link", beep: "boop"]]}
        />
        """)

      assert link = find_one(html, "a[aria-label='Go to page 1']")
      assert attribute(link, "beep") == "boop"
      assert attribute(link, "class") == "p-link"

      # current link attributes are unchanged
      assert link = find_one(html, "a[aria-label='Go to page 2']")
      assert attribute(link, "beep") == nil
      assert attribute(link, "class") == "pagination-link is-current"
    end

    test "allows to overwrite current attributes" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination
          meta={@meta}
          path="/posts"
          opts={[current_link_attrs: [class: "link is-active", beep: "boop"]]}
        />
        """)

      assert link = find_one(html, "a[aria-label='Go to page 1']")
      assert attribute(link, "class") == "pagination-link"
      assert attribute(link, "data-phx-link") == "patch"
      assert attribute(link, "data-phx-link-state") == "push"
      assert attribute(link, "href") == "/posts?limit=10"
      assert text(link) == "1"

      assert link = find_one(html, "a[aria-label='Go to page 2']")
      assert attribute(link, "beep") == "boop"
      assert attribute(link, "class") == "link is-active"
      assert attribute(link, "data-phx-link") == "patch"
      assert attribute(link, "data-phx-link-state") == "push"
      assert href = attribute(link, "href")
      assert_urls_match(href, "/posts?offset=10&limit=10")
      assert text(link) == "2"
    end

    test "allows to overwrite pagination link aria label" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination
          meta={@meta}
          path="/posts"
          opts={[pagination_link_aria_label: &"On to page #{&1}"]}
        />
        """)

      assert link = find_one(html, "a[aria-label='On to page 1']")
      assert attribute(link, "class") == "pagination-link"
      assert attribute(link, "data-phx-link") == "patch"
      assert attribute(link, "data-phx-link-state") == "push"
      assert attribute(link, "href") == "/posts?limit=10"
      assert text(link) == "1"

      assert link = find_one(html, "a[aria-label='On to page 2']")
      assert attribute(link, "class") == "pagination-link is-current"
      assert attribute(link, "data-phx-link") == "patch"
      assert attribute(link, "data-phx-link-state") == "push"
      assert href = attribute(link, "href")
      assert_urls_match(href, "/posts?offset=10&limit=10")
      assert text(link) == "2"
    end

    test "adds order parameters to links" do
      assigns = %{
        meta:
          build(
            :meta_on_second_page,
            ash_pagify: %AshPagify{
              order_by: [name: :asc, author: :desc],
              offset: 10,
              limit: 10
            }
          )
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" />
        """)

      default_query = [
        limit: 10,
        order_by: ["name", "-author"]
      ]

      expected_query = fn
        1 -> default_query
        offset -> Keyword.put(default_query, :offset, offset)
      end

      assert previous = find_one(html, "a:fl-contains('Previous')")
      assert attribute(previous, "class") == "pagination-previous"
      assert attribute(previous, "data-phx-link") == "patch"
      assert attribute(previous, "data-phx-link-state") == "push"
      assert href = attribute(previous, "href")
      assert_urls_match(href, "/posts", expected_query.(1))

      assert one = find_one(html, "a[aria-label='Go to page 1']")
      assert attribute(one, "class") == "pagination-link"
      assert attribute(one, "data-phx-link") == "patch"
      assert attribute(one, "data-phx-link-state") == "push"
      assert href = attribute(one, "href")
      assert_urls_match(href, "/posts", expected_query.(1))

      assert next = find_one(html, "a:fl-contains('Next')")
      assert attribute(next, "class") == "pagination-next"
      assert attribute(next, "data-phx-link") == "patch"
      assert attribute(next, "data-phx-link-state") == "push"
      assert href = attribute(next, "href")
      assert_urls_match(href, "/posts", expected_query.(20))
    end

    test "hides default order and limit" do
      assigns = %{
        meta:
          build(
            :meta_on_second_page,
            ash_pagify: %AshPagify{
              limit: 15,
              order_by: [name: :asc]
            },
            resource: Post
          )
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" />
        """)

      assert prev = find_one(html, "a:fl-contains('Previous')")
      assert href = attribute(prev, "href")

      refute href =~ "limit="
      refute href =~ "order_by[]="
    end

    test "does not require path when passing event" do
      assigns = %{meta: build(:meta_on_second_page)}

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} on_paginate={JS.push("paginate")} />
        """)

      assert link = find_one(html, "a:fl-contains('Previous')")
      assert attribute(link, "class") == "pagination-previous"
      assert attribute(link, "phx-value-offset") == "0"
      assert attribute(link, "href") == "#"
      assert phx_click = attribute(link, "phx-click")
      assert Jason.decode!(phx_click) == [["push", %{"event" => "paginate"}]]
    end

    test "raises if neither path nor on_paginate are passed" do
      assigns = %{meta: build(:meta_on_second_page)}

      assert_raise PathOrJSError,
                   fn ->
                     rendered_to_string(~H"""
                     <AshPagify.Components.pagination meta={@meta} />
                     """)
                   end
    end

    test "adds filter_form parameters to links" do
      filter_form = %{
        "components" => %{
          "0" => %{
            "field" => :tax_scientific_name,
            "negated?" => false,
            "operator" => :in,
            "path" => "",
            "value" => ["Post 1", "Post 2"]
          },
          "1" => %{
            "components" => %{
              "0" => %{
                "field" => :comments_count,
                "negated?" => false,
                "operator" => :greater_than_or_equal,
                "path" => "",
                "value" => "2"
              },
              "1" => %{
                "field" => :comments_count,
                "negated?" => false,
                "operator" => :less_than_or_equal,
                "path" => "",
                "value" => "5"
              }
            },
            "negated" => false,
            "operator" => "and"
          }
        },
        "negated" => false,
        "operator" => "and"
      }

      assigns = %{
        meta:
          build(
            :meta_on_second_page,
            ash_pagify: %AshPagify{
              offset: 10,
              limit: 10,
              filter_form: filter_form
            },
            resource: Post
          )
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" />
        """)

      default_query = [
        limit: 10,
        filter_form: filter_form
      ]

      expected_query = fn
        1 -> default_query
        offset -> Keyword.put(default_query, :offset, offset)
      end

      assert previous = find_one(html, "a:fl-contains('Previous')")
      assert attribute(previous, "class") == "pagination-previous"
      assert attribute(previous, "data-phx-link") == "patch"
      assert attribute(previous, "data-phx-link-state") == "push"
      assert href = attribute(previous, "href")
      assert_urls_match(href, "/posts", expected_query.(1))

      assert one = find_one(html, "a[aria-label='Go to page 1']")
      assert attribute(one, "class") == "pagination-link"
      assert attribute(one, "data-phx-link") == "patch"
      assert attribute(one, "data-phx-link-state") == "push"
      assert href = attribute(one, "href")
      assert_urls_match(href, "/posts", expected_query.(1))

      assert next = find_one(html, "a:fl-contains('Next')")
      assert attribute(next, "class") == "pagination-next"
      assert attribute(next, "data-phx-link") == "patch"
      assert attribute(next, "data-phx-link-state") == "push"
      assert href = attribute(next, "href")
      assert_urls_match(href, "/posts", expected_query.(20))
    end

    test "does not render ellipsis if total pages <= max pages" do
      # max pages smaller than total pages
      assigns = %{
        meta: build(:meta_on_second_page),
        opts: [page_links: {:ellipsis, 50}]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" opts={@opts} />
        """)

      assert Floki.find(html, ".pagination-ellipsis") == []
      assert html |> Floki.find("a.pagination-link") |> length() == 5

      # max pages equal to total pages
      assigns = %{
        meta: build(:meta_on_second_page),
        opts: [page_links: {:ellipsis, 5}]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" opts={@opts} />
        """)

      assert Floki.find(html, ".pagination-ellipsis") == []
      assert html |> Floki.find("a.pagination-link") |> length() == 5
    end

    test "renders end ellipsis and last page link when on page 1" do
      assigns = %{
        meta: build(:meta_on_first_page, total_pages: 20),
        opts: [page_links: {:ellipsis, 5}]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" opts={@opts} />
        """)

      assert html |> Floki.find(".pagination-ellipsis") |> length() == 1
      assert html |> Floki.find("a.pagination-link") |> length() == 6

      assert find_one(html, "a[aria-label='Go to page 20']")

      for i <- 1..5 do
        assert find_one(html, "a[aria-label='Go to page #{i}']")
      end
    end

    test "renders start ellipsis and first page link when on last page" do
      assigns = %{
        meta: build(:meta_on_first_page, current_page: 20, total_pages: 20),
        opts: [page_links: {:ellipsis, 5}]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" opts={@opts} />
        """)

      assert html |> Floki.find(".pagination-ellipsis") |> length() == 1
      assert html |> Floki.find("a.pagination-link") |> length() == 6

      assert find_one(html, "a[aria-label='Go to page 1']")

      for i <- 16..20 do
        assert find_one(html, "a[aria-label='Go to page #{i}']")
      end
    end

    test "renders ellipses when on even page with even number of max pages" do
      assigns = %{
        meta: build(:meta_on_first_page, current_page: 12, total_pages: 20),
        opts: [page_links: {:ellipsis, 6}]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" opts={@opts} />
        """)

      assert html |> Floki.find(".pagination-ellipsis") |> length() == 2
      assert html |> Floki.find("a.pagination-link") |> length() == 8

      assert find_one(html, "a[aria-label='Go to page 1']")
      assert find_one(html, "a[aria-label='Go to page 20']")

      for i <- 10..15 do
        assert find_one(html, "a[aria-label='Go to page #{i}']")
      end
    end

    test "renders ellipses when on odd page with odd number of max pages" do
      assigns = %{
        meta: build(:meta_on_first_page, current_page: 11, total_pages: 20),
        opts: [page_links: {:ellipsis, 5}]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" opts={@opts} />
        """)

      assert html |> Floki.find(".pagination-ellipsis") |> length() == 2
      assert html |> Floki.find("a.pagination-link") |> length() == 7

      assert find_one(html, "a[aria-label='Go to page 1']")
      assert find_one(html, "a[aria-label='Go to page 20']")

      for i <- 9..13 do
        assert find_one(html, "a[aria-label='Go to page #{i}']")
      end
    end

    test "renders ellipses when on even page with odd number of max pages" do
      assigns = %{
        meta: build(:meta_on_first_page, current_page: 10, total_pages: 20),
        opts: [page_links: {:ellipsis, 5}]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" opts={@opts} />
        """)

      assert html |> Floki.find(".pagination-ellipsis") |> length() == 2
      assert html |> Floki.find("a.pagination-link") |> length() == 7

      assert find_one(html, "a[aria-label='Go to page 1']")
      assert find_one(html, "a[aria-label='Go to page 20']")

      for i <- 8..12 do
        assert find_one(html, "a[aria-label='Go to page #{i}']")
      end
    end

    test "renders ellipses when on odd page with even number of max pages" do
      assigns = %{
        meta: build(:meta_on_first_page, current_page: 11, total_pages: 20),
        opts: [page_links: {:ellipsis, 5}]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" opts={@opts} />
        """)

      assert html |> Floki.find(".pagination-ellipsis") |> length() == 2
      assert html |> Floki.find("a.pagination-link") |> length() == 7

      assert find_one(html, "a[aria-label='Go to page 1']")
      assert find_one(html, "a[aria-label='Go to page 20']")

      for i <- 9..13 do
        assert find_one(html, "a[aria-label='Go to page #{i}']")
      end
    end

    test "renders end ellipsis when on page close to the beginning" do
      assigns = %{
        meta: build(:meta_on_first_page, current_page: 2, total_pages: 20),
        opts: [page_links: {:ellipsis, 5}]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" opts={@opts} />
        """)

      assert html |> Floki.find(".pagination-ellipsis") |> length() == 1
      assert html |> Floki.find("a.pagination-link") |> length() == 6

      assert find_one(html, "a[aria-label='Go to page 20']")

      for i <- 1..5 do
        assert find_one(html, "a[aria-label='Go to page #{i}']")
      end
    end

    test "renders start ellipsis when on page close to the end" do
      assigns = %{
        meta: build(:meta_on_first_page, current_page: 18, total_pages: 20),
        opts: [page_links: {:ellipsis, 5}]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" opts={@opts} />
        """)

      assert html |> Floki.find(".pagination-ellipsis") |> length() == 1
      assert html |> Floki.find("a.pagination-link") |> length() == 6

      assert find_one(html, "a[aria-label='Go to page 1']")

      for i <- 16..20 do
        assert find_one(html, "a[aria-label='Go to page #{i}']")
      end
    end

    test "allows to overwrite ellipsis attributes and content" do
      assigns = %{
        meta: build(:meta_on_first_page, current_page: 10, total_pages: 20),
        opts: [
          page_links: {:ellipsis, 5},
          ellipsis_attrs: [class: "dotdotdot", title: "dot"],
          ellipsis_content: "dot dot dot"
        ]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.pagination meta={@meta} path="/posts" opts={@opts} />
        """)

      assert [el, _] = Floki.find(html, "span[class='dotdotdot']")
      assert text(el) == "dot dot dot"
    end

    test "does not render anything if meta has errors" do
      {:error, meta} = AshPagify.validate(Post, %{offset: -1})
      assigns = %{meta: meta}

      assert parse_heex(~H"""
             <AshPagify.Components.pagination meta={@meta} path="/posts" />
             """) == []
    end
  end

  describe "table/1" do
    test "allows to set table attributes" do
      # attribute from global config
      html = render_table(%{opts: []})
      assert table = find_one(html, "table")
      assert attribute(table, "class") == nil

      html = render_table(%{opts: [table_attrs: [class: "funky-table"]]})
      assert table = find_one(html, "table")
      assert attribute(table, "class") == "funky-table"
    end

    test "optionally adds a table container" do
      html = render_table(%{opts: []})
      assert Floki.find(html, "#some_table_container") == []

      html = render_table(%{opts: [container: true]})
      assert find_one(html, "#some_table_container")
    end

    test "allows to set container attributes" do
      html =
        render_table(%{
          opts: [
            container_attrs: [class: "container", data_some: "thing"],
            container: true
          ]
        })

      assert container = find_one(html, "div.container")
      assert attribute(container, "data_some") == "thing"
    end

    test "allows to set tbody attributes" do
      html =
        render_table(%{
          opts: [
            tbody_attrs: [class: "mango_body"],
            container: true
          ]
        })

      assert find_one(html, "tbody.mango_body")
    end

    test "setting thead attributes" do
      html =
        render_table(%{
          opts: [
            thead_attrs: [class: "text-left text-zinc-500 leading-6"],
            container: true
          ]
        })

      assert find_one(html, "thead.text-left.text-zinc-500.leading-6")
    end

    test "allows to set id on table, tbody and container" do
      html = render_table(%{id: "some_id", opts: [container: true]})
      assert find_one(html, "div#some_id_container")
      assert find_one(html, "table#some_id")
      assert find_one(html, "tbody#some_id_tbody")
    end

    test "sets default ID based on resource module" do
      assigns = %{
        meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post},
        items: ["George"]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table items={@items} meta={@meta} on_sort={JS.push("sort")}>
          <:col></:col>
        </AshPagify.Components.table>
        """)

      assert find_one(html, "table#post_table")
      assert find_one(html, "tbody#post_table_tbody")
    end

    test "sets default ID without resource module" do
      assigns = %{}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          items={["George"]}
          meta={%AshPagify.Meta{ash_pagify: %AshPagify{}}}
          on_sort={JS.push("sort")}
          opts={[container: true]}
        >
          <:col></:col>
        </AshPagify.Components.table>
        """)

      assert find_one(html, "div#sortable_table_container")
      assert find_one(html, "table#sortable_table")
      assert find_one(html, "tbody#sortable_table_tbody")
    end

    test "does not set row ID if items are not a stream" do
      assigns = %{
        meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post},
        items: ["George"]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table items={@items} meta={@meta} on_sort={JS.push("sort")}>
          <:col></:col>
        </AshPagify.Components.table>
        """)

      assert tr = find_one(html, "tbody tr")
      assert attribute(tr, "id") == nil
    end

    test "allows to set row ID function" do
      assigns = %{
        meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post},
        items: [%Post{id: 1, name: "George"}, %Post{id: 2, name: "Mary"}],
        row_id: &"posts-#{&1.name}"
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table items={@items} meta={@meta} row_id={@row_id} on_sort={JS.push("sort")}>
          <:col></:col>
        </AshPagify.Components.table>
        """)

      assert [tr_1, tr_2] = Floki.find(html, "tbody tr")
      assert attribute(tr_1, "id") == "posts-George"
      assert attribute(tr_2, "id") == "posts-Mary"
    end

    test "uses default row ID function if items are a stream" do
      assigns = %{
        meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post},
        stream: LiveStream.new(:posts, 0, [%Post{id: 1}, %Post{id: 2}], [])
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table items={@stream} meta={@meta} on_sort={JS.push("sort")}>
          <:col></:col>
        </AshPagify.Components.table>
        """)

      assert [tr_1, tr_2] = Floki.find(html, "tbody tr")
      assert attribute(tr_1, "id") == "posts-1"
      assert attribute(tr_2, "id") == "posts-2"
    end

    test "allows to override default row item function" do
      assigns = %{
        meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post},
        items: [%Post{name: "George"}],
        row_item: fn item -> Map.update!(item, :name, &String.upcase/1) end
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          items={@items}
          meta={@meta}
          row_item={@row_item}
          on_sort={JS.push("sort")}
        >
          <:col :let={p}><%= p.name %></:col>
        </AshPagify.Components.table>
        """)

      assert td = find_one(html, "tbody td")
      assert text(td) == "GEORGE"
    end

    test "allows to set tr and td classes via keyword lists" do
      html =
        render_table(%{
          opts: [
            thead_tr_attrs: [class: "mungo"],
            thead_th_attrs: [class: "bean"],
            tbody_tr_attrs: [class: "salt"],
            tbody_td_attrs: [class: "tolerance"]
          ]
        })

      assert find_one(html, "tr.mungo")
      assert [_, _, _, _, _] = Floki.find(html, "th.bean")
      assert find_one(html, "tr.salt")
      assert [_, _, _, _, _] = Floki.find(html, "td.tolerance")
    end

    test "evaluates attrs function for tr" do
      assigns = %{}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          path="/posts"
          items={[
            %{name: "Bruce Wayne", age: 42, occupation: "Superhero"},
            %{name: "April O'Neil", age: 39, occupation: "Crime Reporter"}
          ]}
          opts={[
            tbody_tr_attrs: fn item, _assigns ->
              class =
                item.occupation
                |> String.downcase()
                |> String.replace(" ", "-")

              [class: class]
            end
          ]}
          meta={%AshPagify.Meta{ash_pagify: %AshPagify{}}}
        >
          <:col></:col>
        </AshPagify.Components.table>
        """)

      assert find_one(html, "tr.superhero")
      assert find_one(html, "tr.crime-reporter")
    end

    test "evaluates tbody_td_attrs function for col slot / td" do
      assigns = %{}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          path="/posts"
          items={[
            %{name: "Mary Cratsworth-Shane", age: 99},
            %{name: "Bart Harley-Jarvis", age: 1}
          ]}
          meta={%AshPagify.Meta{ash_pagify: %AshPagify{}}}
        >
          <:col tbody_td_attrs={
            fn item, _assigns ->
              [class: if(item.age > 17, do: "adult", else: "child")]
            end
          }>
          </:col>
        </AshPagify.Components.table>
        """)

      assert find_one(html, "td.adult")
      assert find_one(html, "td.child")
    end

    test "evaluates tbody_td_attrs function in action columns" do
      assigns = %{
        attrs_fun: fn item, _assigns ->
          [class: if(item.age > 17, do: "adult", else: "child")]
        end
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          items={[
            %{name: "Mary Cratsworth-Shane", age: 99},
            %{name: "Bart Harley-Jarvis", age: 1}
          ]}
          meta={%AshPagify.Meta{ash_pagify: %AshPagify{}}}
          on_sort={%JS{}}
        >
          <:col :let={u} label="Name"><%= u.name %></:col>
          <:action label="Buttons" tbody_td_attrs={@attrs_fun}>some action</:action>
        </AshPagify.Components.table>
        """)

      assert find_one(html, "td.adult")
      assert find_one(html, "td.child")
    end

    test "allows to set td class on action" do
      assigns = %{}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          path="/posts"
          items={[%{}]}
          meta={%AshPagify.Meta{ash_pagify: %AshPagify{}}}
          opts={[tbody_td_attrs: [class: "tolerance"]]}
        >
          <:col></:col>
          <:action>action</:action>
        </AshPagify.Components.table>
        """)

      assert [_, _] = Floki.find(html, "td.tolerance")
    end

    test "adds additional attributes to th" do
      assigns = %{}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          path="/posts"
          items={[%{name: "George", age: 8}]}
          meta={%AshPagify.Meta{ash_pagify: %AshPagify{}}}
        >
          <:col :let={post} thead_th_attrs={[class: "name-header"]}>
            <%= post.name %>
          </:col>
          <:col :let={post} thead_th_attrs={[class: "age-header"]}>
            <%= post.age %>
          </:col>
          <:action :let={post} thead_th_attrs={[class: "action-header"]}>
            <.link navigate={"/show/post/#{post.name}"}>Show Post</.link>
          </:action>
        </AshPagify.Components.table>
        """)

      assert find_one(html, "th.name-header")
      assert find_one(html, "th.age-header")
      assert find_one(html, "th.action-header")
    end

    test "adds additional attributes to td" do
      assigns = %{}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          path="/posts"
          items={[%{name: "George", age: 8}]}
          meta={%AshPagify.Meta{ash_pagify: %AshPagify{}}}
        >
          <:col :let={post} tbody_td_attrs={[class: "name-column"]}>
            <%= post.name %>
          </:col>
          <:col :let={post} tbody_td_attrs={[class: "age-column"]}>
            <%= post.age %>
          </:col>
          <:action :let={post} tbody_td_attrs={[class: "action-column"]}>
            <.link navigate={"/show/post/#{post.name}"}>Show Post</.link>
          </:action>
        </AshPagify.Components.table>
        """)

      assert find_one(html, "td.name-column")
      assert find_one(html, "td.age-column")
      assert find_one(html, "td.action-column")
    end

    test "overrides table_th_attrs with thead_th_attrs in col" do
      assigns = %{
        meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post},
        items: [%{name: "George", age: 8}],
        opts: [thead_th_attrs: [class: "default-th-class"]]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table items={@items} meta={@meta} on_sort={%JS{}} opts={@opts}>
          <:col :let={i} thead_th_attrs={[class: "name-th-class"]}><%= i.name %></:col>
          <:col :let={i}><%= i.age %></:col>
        </AshPagify.Components.table>
        """)

      assert {"th", [{"class", "name-th-class"}], _} =
               find_one(html, "th:first-child")

      assert {"th", [{"class", "default-th-class"}], _} =
               find_one(html, "th:last-child")
    end

    test "merges table_th_attrs with class from col" do
      assigns = %{
        meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post},
        items: [%{name: "George", age: 8}],
        opts: [thead_th_attrs: [class: "default-th-class"]]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table items={@items} meta={@meta} on_sort={%JS{}} opts={@opts}>
          <:col :let={i} thead_th_attrs={[class: "name-th-class"]} class="name-th-col-class">
            <%= i.name %>
          </:col>
          <:col :let={i} class="name-th-col-class"><%= i.age %></:col>
        </AshPagify.Components.table>
        """)

      assert {"th", [{"class", "name-th-class name-th-col-class"}], _} =
               find_one(html, "th:first-child")

      assert {"th", [{"class", "default-th-class name-th-col-class"}], _} =
               find_one(html, "th:last-child")
    end

    test "evaluates table th_wrapper_attrs" do
      assigns = %{
        meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post},
        items: [%{name: "George", age: 8}],
        opts: [th_wrapper_attrs: [class: "default-th-wrapper-class"]]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table items={@items} meta={@meta} on_sort={%JS{}} opts={@opts}>
          <:col :let={i} field={:name}><%= i.name %></:col>
          <:col :let={i}><%= i.age %></:col>
        </AshPagify.Components.table>
        """)

      assert {"th", [], [{"span", [{"class", "default-th-wrapper-class"}], _}]} =
               find_one(html, "th:first-child")
    end

    test "overrides th_wrapper_attrs" do
      assigns = %{
        meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post},
        items: [%{name: "George", age: 8}],
        opts: [th_wrapper_attrs: [class: "default-th-wrapper-class"]]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table items={@items} meta={@meta} on_sort={%JS{}} opts={@opts}>
          <:col :let={i} field={:name} th_wrapper_attrs={[class: "name-th-wrapper-class"]}>
            <%= i.name %>
          </:col>
          <:col :let={i} field={:age}><%= i.age %></:col>
        </AshPagify.Components.table>
        """)

      assert {"th", [], [{"span", [{"class", "name-th-wrapper-class"}], _}]} =
               find_one(html, "th:first-child")

      assert {"th", [], [{"span", [{"class", "default-th-wrapper-class"}], _}]} =
               find_one(html, "th:last-child")
    end

    test "overrides table_td_attrs with tbody_td_attrs in col" do
      assigns = %{
        meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post},
        items: [%{name: "George", age: 8}],
        opts: [tbody_td_attrs: [class: "default-td-class"]]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table items={@items} meta={@meta} on_sort={%JS{}} opts={@opts}>
          <:col :let={i} tbody_td_attrs={[class: "name-td-class"]}><%= i.name %></:col>
          <:col :let={i}><%= i.age %></:col>
        </AshPagify.Components.table>
        """)

      assert {"td", [{"class", "name-td-class"}], _} =
               find_one(html, "td:first-child")

      assert {"td", [{"class", "default-td-class"}], _} =
               find_one(html, "td:last-child")
    end

    test "merges table_td_attrs with class from col" do
      assigns = %{
        meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post},
        items: [%{name: "George", age: 8}],
        opts: [tbody_td_attrs: [class: "default-td-class"]]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table items={@items} meta={@meta} on_sort={%JS{}} opts={@opts}>
          <:col :let={i} tbody_td_attrs={[class: "name-td-class"]} class="name-td-col-class">
            <%= i.name %>
          </:col>
          <:col :let={i} class="name-td-col-class"><%= i.age %></:col>
        </AshPagify.Components.table>
        """)

      assert {"td", [{"class", "name-td-class name-td-col-class"}], _} =
               find_one(html, "td:first-child")

      assert {"td", [{"class", "default-td-class name-td-col-class"}], _} =
               find_one(html, "td:last-child")
    end

    test "overrides table_th_attrs with thead_th_attrs in action columns" do
      assigns = %{
        meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post},
        items: [%{name: "George", age: 8}],
        opts: [thead_th_attrs: [class: "default-th-class"]]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table items={@items} meta={@meta} on_sort={%JS{}} opts={@opts}>
          <:col :let={i}><%= i.name %></:col>
          <:action thead_th_attrs={[class: "action-1-th-class"]}>action 1</:action>
          <:action>action 2</:action>
        </AshPagify.Components.table>
        """)

      assert {"th", [{"class", "action-1-th-class"}], _} =
               find_one(html, "th:nth-child(2)")

      assert {"th", [{"class", "default-th-class"}], _} =
               find_one(html, "th:last-child")
    end

    test "merges table_th_attrs with class in action columns" do
      assigns = %{
        meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post},
        items: [%{name: "George", age: 8}],
        opts: [thead_th_attrs: [class: "default-th-class"]]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table items={@items} meta={@meta} on_sort={%JS{}} opts={@opts}>
          <:col :let={i}><%= i.name %></:col>
          <:action thead_th_attrs={[class: "action-1-th-class"]} class="action-1-col-class">
            action 1
          </:action>
          <:action class="action-2-col-class">action 2</:action>
        </AshPagify.Components.table>
        """)

      assert {"th", [{"class", "action-1-th-class action-1-col-class"}], _} =
               find_one(html, "th:nth-child(2)")

      assert {"th", [{"class", "default-th-class action-2-col-class"}], _} =
               find_one(html, "th:last-child")
    end

    test "overrides table_td_attrs with tbody_td_attrs in action columns" do
      assigns = %{
        meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post},
        items: [%{name: "George", age: 8}],
        opts: [tbody_td_attrs: [class: "default-td-class"]]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table items={@items} meta={@meta} on_sort={%JS{}} opts={@opts}>
          <:col :let={i}><%= i.name %></:col>
          <:action tbody_td_attrs={[class: "action-1-td-class"]}>action 1</:action>
          <:action>action 2</:action>
        </AshPagify.Components.table>
        """)

      assert {"td", [{"class", "action-1-td-class"}], _} =
               find_one(html, "td:nth-child(2)")

      assert {"td", [{"class", "default-td-class"}], _} =
               find_one(html, "td:last-child")
    end

    test "merges table_td_attrs with class in action columns" do
      assigns = %{
        meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post},
        items: [%{name: "George", age: 8}],
        opts: [tbody_td_attrs: [class: "default-td-class"]]
      }

      html =
        parse_heex(~H"""
        <AshPagify.Components.table items={@items} meta={@meta} on_sort={%JS{}} opts={@opts}>
          <:col :let={i}><%= i.name %></:col>
          <:action tbody_td_attrs={[class: "action-1-td-class"]} class="action-1-col-class">
            action 1
          </:action>
          <:action class="action-2-col-class">action 2</:action>
        </AshPagify.Components.table>
        """)

      assert {"td", [{"class", "action-1-td-class action-1-col-class"}], _} =
               find_one(html, "td:nth-child(2)")

      assert {"td", [{"class", "default-td-class action-2-col-class"}], _} =
               find_one(html, "td:last-child")
    end

    test "doesn't render table if items list is empty" do
      assert [{"p", [], ["No results."]}] = render_table(%{items: []})
    end

    test "displays headers for action col" do
      assigns = %{meta: %AshPagify.Meta{ash_pagify: %AshPagify{}}}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table path="/posts" items={[%{}]} meta={@meta}>
          <:col></:col>
          <:action label="Buttons"></:action>
        </AshPagify.Components.table>
        """)

      assert th = find_one(html, "th:fl-contains('Buttons')")
      assert Floki.children(th, include_text: false) == []
    end

    test "displays headers without sorting function" do
      html = render_table(%{})
      assert th = find_one(html, "th:fl-contains('Age')")
      assert Floki.children(th, include_text: false) == []
    end

    test "displays headers without sorting function with th_wrapper_attrs" do
      html =
        render_table(%{
          opts: [
            th_wrapper_attrs: [class: "default-th-wrapper-class"]
          ]
        })

      assert th = find_one(html, "th span:fl-contains('Age')")
      assert Floki.children(th, include_text: false) == []
    end

    test "conditionally hides an action column" do
      assigns = %{meta: %AshPagify.Meta{ash_pagify: %AshPagify{}}}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table path="/posts" items={[%{}]} meta={@meta}>
          <:col></:col>
          <:action label="Buttons"><a href="#">Show Post</a></:action>
        </AshPagify.Components.table>
        """)

      assert find_one(html, "th:fl-contains('Buttons')")

      html =
        parse_heex(~H"""
        <AshPagify.Components.table path="/posts" items={[%{}]} meta={@meta}>
          <:col></:col>
          <:action label="Buttons" show={true} hide={false}></:action>
        </AshPagify.Components.table>
        """)

      assert find_one(html, "th:fl-contains('Buttons')")

      html =
        parse_heex(~H"""
        <AshPagify.Components.table path="/posts" items={[%{}]} meta={@meta}>
          <:col></:col>
          <:action label="Buttons" show={true} hide={true}></:action>
        </AshPagify.Components.table>
        """)

      assert [] = Floki.find(html, "th:fl-contains('Buttons')")

      html =
        parse_heex(~H"""
        <AshPagify.Components.table path="/posts" items={[%{}]} meta={@meta}>
          <:col></:col>
          <:action label="Buttons" show={false} hide={true}></:action>
        </AshPagify.Components.table>
        """)

      assert [] = Floki.find(html, "th:fl-contains('Buttons')")

      html =
        parse_heex(~H"""
        <AshPagify.Components.table path="/posts" items={[%{}]} meta={@meta}>
          <:col></:col>
          <:action label="Buttons" show={false} hide={false}></:action>
        </AshPagify.Components.table>
        """)

      assert [] = Floki.find(html, "th:fl-contains('Buttons')")
    end

    test "displays headers with sorting function" do
      html = render_table(%{})

      assert a = find_one(html, "th a:fl-contains('Name')")
      assert attribute(a, "data-phx-link") == "patch"
      assert attribute(a, "data-phx-link-state") == "push"

      assert href = attribute(a, "href")
      assert_urls_match(href, "/posts?order_by[]=name")
    end

    test "uses phx-click with on_sort without path" do
      html =
        render_table(%{
          path: nil,
          on_sort: JS.push("sort")
        })

      assert a = find_one(html, "th a:fl-contains('Name')")
      assert attribute(a, "data-phx-link") == nil
      assert attribute(a, "data-phx-link-state") == nil
      assert attribute(a, "href") == "#"
      assert attribute(a, "phx-value-order") == "name"
      assert phx_click = attribute(a, "phx-click")
      assert Jason.decode!(phx_click) == [["push", %{"event" => "sort"}]]
    end

    test "application of custom sort directions per column" do
      assigns = %{
        meta: %AshPagify.Meta{
          ash_pagify: %AshPagify{
            order_by: [ttfb: :desc_nils_last]
          }
        },
        items: [
          %{
            ttfb: 2
          },
          %{
            ttfb: 1
          },
          %{
            ttfb: nil
          }
        ],
        ttfb_directions: {:asc_nils_first, :desc_nils_last}
      }

      html =
        ~H"""
        <AshPagify.Components.table id="metrics-table" items={@items} meta={@meta} path="/navigations">
          <:col :let={navigation} label="TTFB" field={:ttfb} directions={@ttfb_directions}>
            <%= navigation.ttfb %>
          </:col>
        </AshPagify.Components.table>
        """
        |> rendered_to_string()
        |> Floki.parse_fragment!()

      ttfb_sort_href =
        html
        |> find_one("thead th a:fl-contains('TTFB')")
        |> attribute("href")

      %URI{query: query} = URI.parse(ttfb_sort_href)
      decoded_query = Query.decode(query)

      # assert href representing opposite direction of initial table sort
      assert %{"order_by" => ["++ttfb"]} = decoded_query
    end

    test "supports a function/args tuple as path" do
      html = render_table(%{path: {&route_helper/3, @route_helper_opts}})
      assert a = find_one(html, "th a:fl-contains('Name')")
      assert href = attribute(a, "href")
      assert_urls_match(href, "/posts?order_by[]=name")
    end

    test "supports a function as path" do
      html = render_table(%{path: &path_func/1})
      assert a = find_one(html, "th a:fl-contains('Name')")

      assert href = attribute(a, "href")
      assert_urls_match(href, "/posts?&order_by[]=name")
    end

    test "supports a URI string as path" do
      html = render_table(%{path: "/posts"})
      assert a = find_one(html, "th a:fl-contains('Name')")

      href = attribute(a, "href")
      uri = URI.parse(href)
      assert uri.path == "/posts"
      assert URI.decode_query(uri.query) == %{"order_by[]" => "name"}
    end

    test "displays headers with safe HTML values in action col" do
      assigns = %{}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          on_sort={JS.push("sort")}
          id="user-table"
          items={[%{name: "George"}]}
          meta={%AshPagify.Meta{ash_pagify: %AshPagify{}}}
        >
          <:col :let={post}>
            <%= post.name %>
          </:col>
          <:action :let={post} label={{:safe, "<span>Hello</span>"}}>
            <%= post.name %>
          </:action>
        </AshPagify.Components.table>
        """)

      assert span = find_one(html, "th span")
      assert text(span) == "Hello"
    end

    test "displays headers with safe HTML values" do
      assigns = %{}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          id="user-table"
          on_sort={JS.push("sort")}
          items={[%{name: "George"}]}
          meta={%AshPagify.Meta{ash_pagify: %AshPagify{}}}
        >
          <:col :let={post} label={{:safe, "<span>Hello</span>"}} field={:name}>
            <%= post.name %>
          </:col>
        </AshPagify.Components.table>
        """)

      assert span = find_one(html, "th a span")
      assert text(span) == "Hello"
    end

    test "adds aria-sort attribute only to first ordered field" do
      html =
        render_table(%{
          meta: %AshPagify.Meta{
            ash_pagify: %AshPagify{
              order_by: [email: :asc, name: :desc]
            }
          }
        })

      assert [th_name, th_email, th_age, th_species, _] = Floki.find(html, "th")
      assert attribute(th_name, "aria-sort") == nil
      assert attribute(th_email, "aria-sort") == "ascending"
      assert attribute(th_age, "aria-sort") == nil
      assert attribute(th_species, "aria-sort") == nil

      html =
        render_table(%{
          meta: %AshPagify.Meta{
            ash_pagify: %AshPagify{
              order_by: [name: :desc, email: :asc]
            }
          }
        })

      assert [th_name, th_email, th_age, th_species, _] = Floki.find(html, "th")
      assert attribute(th_name, "aria-sort") == "descending"
      assert attribute(th_email, "aria-sort") == nil
      assert attribute(th_age, "aria-sort") == nil
      assert attribute(th_species, "aria-sort") == nil

      html =
        render_table(%{
          meta: %AshPagify.Meta{
            ash_pagify: %AshPagify{order_by: []}
          }
        })

      assert [th_name, th_email, th_age, th_species, _] = Floki.find(html, "th")
      assert attribute(th_name, "aria-sort") == nil
      assert attribute(th_email, "aria-sort") == nil
      assert attribute(th_age, "aria-sort") == nil
      assert attribute(th_species, "aria-sort") == nil
    end

    test "renders links with click handler" do
      html = render_table(%{on_sort: JS.push("sort"), path: nil})

      assert a = find_one(html, "th a:fl-contains('Name')")
      assert attribute(a, "href") == "#"
      assert attribute(a, "phx-value-order") == "name"
      assert phx_click = attribute(a, "phx-click")
      assert Jason.decode!(phx_click) == [["push", %{"event" => "sort"}]]

      assert a = find_one(html, "th a:fl-contains('Email')")
      assert attribute(a, "href") == "#"
      assert attribute(a, "phx-value-order") == "email"
      assert phx_click = attribute(a, "phx-click")
      assert Jason.decode!(phx_click) == [["push", %{"event" => "sort"}]]
    end

    test "adds phx-target to header links" do
      html = render_table(%{on_sort: JS.push("sort"), path: nil, target: "here"})

      assert a = find_one(html, "th a:fl-contains('Name')")
      assert attribute(a, "href") == "#"
      assert attribute(a, "phx-target") == "here"
      assert attribute(a, "phx-value-order") == "name"
      assert phx_click = attribute(a, "phx-click")
      assert Jason.decode!(phx_click) == [["push", %{"event" => "sort"}]]
    end

    test "checks for sortability if for option is set" do
      # without :for option
      html = render_table(%{})

      assert find_one(html, "a:fl-contains('Name')")
      assert find_one(html, "a:fl-contains('Species')")

      # with :for assign
      html = render_table(%{meta: %AshPagify.Meta{ash_pagify: %AshPagify{}, resource: Post}})

      assert find_one(html, "a:fl-contains('Name')")
      assert [] = Floki.find(html, "a:fl-contains('Species')")
    end

    test "hides default order and limit" do
      html =
        render_table(%{
          meta:
            build(
              :meta_on_second_page,
              ash_pagify: %AshPagify{
                limit: 15,
                order_by: [name: :desc]
              },
              resource: Post
            )
        })

      assert link = find_one(html, "a:fl-contains('Name')")
      assert href = attribute(link, "href")

      refute href =~ "limit="
      refute href =~ "order_by[]="
    end

    test "renders order direction symbol" do
      html =
        render_table(%{
          meta: %AshPagify.Meta{
            ash_pagify: %AshPagify{order_by: [name: :asc]}
          }
        })

      assert Floki.find(
               html,
               "a:fl-contains('Email') + span.order-direction"
             ) == []

      html =
        render_table(%{
          meta: %AshPagify.Meta{
            ash_pagify: %AshPagify{order_by: [email: :asc]}
          }
        })

      assert span =
               find_one(
                 html,
                 "th a:fl-contains('Email') + span.order-direction"
               )

      assert text(span) == "▴"

      html =
        render_table(%{
          meta: %AshPagify.Meta{
            ash_pagify: %AshPagify{order_by: [email: :desc]}
          }
        })

      assert span =
               find_one(
                 html,
                 "th a:fl-contains('Email') + span.order-direction"
               )

      assert text(span) == "▾"
    end

    test "only renders order direction symbol for first order field" do
      html =
        render_table(%{
          meta: %AshPagify.Meta{
            ash_pagify: %AshPagify{
              order_by: [name: :asc, email: :desc]
            }
          }
        })

      assert span =
               find_one(
                 html,
                 "th a:fl-contains('Name') + span.order-direction"
               )

      assert text(span) == "▴"

      assert Floki.find(
               html,
               "a:fl-contains('Email') + span.order-direction"
             ) == []
    end

    test "allows to set symbol class" do
      html =
        render_table(%{
          meta: %AshPagify.Meta{
            ash_pagify: %AshPagify{order_by: [name: :asc]}
          },
          opts: [symbol_attrs: [class: "other-class"]]
        })

      assert find_one(html, "span.other-class")
    end

    test "allows to override default symbols" do
      html =
        render_table(%{
          meta: %AshPagify.Meta{
            ash_pagify: %AshPagify{order_by: [name: :asc]}
          },
          opts: [symbol_asc: "asc"]
        })

      assert span = find_one(html, "span.order-direction")
      assert text(span) == "asc"

      html =
        render_table(%{
          meta: %AshPagify.Meta{
            ash_pagify: %AshPagify{order_by: [name: :desc]}
          },
          opts: [symbol_desc: "desc"]
        })

      assert span = find_one(html, "span.order-direction")
      assert text(span) == "desc"
    end

    test "allows to set indicator for unsorted column" do
      html =
        render_table(%{
          meta: %AshPagify.Meta{
            ash_pagify: %AshPagify{order_by: [name: :asc]}
          },
          opts: [symbol_unsorted: "random"]
        })

      assert span =
               find_one(
                 html,
                 "th a:fl-contains('Email') + span.order-direction"
               )

      assert text(span) == "random"
    end

    test "renders notice if item list is empty" do
      assert [{"p", [], ["No results."]}] = render_table(%{items: []})
    end

    test "allows to set no_results_content" do
      assert render_table(%{
               items: [],
               opts: [
                 no_results_content: custom_no_results_content()
               ]
             }) == [{"div", [], ["Nothing!"]}]
    end

    test "allows to set loading_content" do
      html =
        render_table(%{
          loading: true,
          items: [],
          opts: [
            loading_items: 1,
            loading_content: custom_loading_content()
          ]
        })

      assert [
               {"table", [{"id", "some_table"}],
                [
                  {"thead", _, _},
                  {
                    "tbody",
                    [{"id", "some_table_tbody"}],
                    [
                      {"tr", [],
                       [
                         {"td", [], [{"div", [], ["It's loading!"]}]},
                         {"td", [], [{"div", [], ["It's loading!"]}]},
                         {"td", [], [{"div", [], ["It's loading!"]}]},
                         {"td", [], [{"div", [], ["It's loading!"]}]},
                         {"td", [], [{"div", [], ["It's loading!"]}]}
                       ]}
                    ]
                  }
                ]}
             ] = html
    end

    test "allows to set error_content" do
      assert render_table(%{
               error: true,
               items: [],
               opts: [
                 error_content: custom_error_content()
               ]
             }) == [{"div", [], ["Crap!"]}]
    end

    test "renders row_click" do
      assigns = %{}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          on_sort={JS.push("sort")}
          id="user-table"
          items={[%{name: "George", id: 1}]}
          meta={%AshPagify.Meta{ash_pagify: %AshPagify{}}}
          row_click={&JS.navigate("/show/#{&1.id}")}
        >
          <:col :let={post} label="Name" field={:name}><%= post.name %></:col>
          <:action :let={post}>
            <.link navigate={"/show/post/#{post.name}"}>Show Post</.link>
          </:action>
        </AshPagify.Components.table>
        """)

      assert [{"table", _, [{"thead", _, _}, {"tbody", _, rows}]}] = html

      # two columns in total, second one is for action
      assert [_, _] = Floki.find(rows, "td")

      # only one column should have phx-click attribute
      assert find_one(rows, "td[phx-click]")
    end

    test "does not render row_click if not set" do
      html = render_table(%{})

      assert [
               {"table", [{"id", "some_table"}, {"class", "some-table"}],
                [
                  {"thead", _, _},
                  {"tbody", _, rows}
                ]}
             ] = html

      assert [] = Floki.find(rows, "td[phx-click]")
    end

    test "renders table action" do
      assigns = %{meta: %AshPagify.Meta{ash_pagify: %AshPagify{}}}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          path="/posts"
          items={[%{name: "George", age: 8}, %{name: "Mary", age: 10}]}
          meta={@meta}
        >
          <:col></:col>
          <:action :let={post} label="Buttons">
            <.link navigate={"/show/post/#{post.name}"}>Show Post</.link>
          </:action>
        </AshPagify.Components.table>
        """)

      assert [
               {"table", _,
                [
                  {"thead", _, _},
                  {"tbody", _, rows}
                ]}
             ] = html

      assert find_one(rows, "a[href='/show/post/Mary']")
      assert find_one(rows, "a[href='/show/post/George']")
    end

    test "does not render action column if option is not set" do
      html = render_table(%{})

      assert [
               {"table", [{"id", "some_table"}, {"class", "some-table"}], [{"thead", _, _}, {"tbody", _, rows}]}
             ] = html

      assert [] = Floki.find(rows, "a")

      # test table has five column
      assert [_, _, _, _, _] = Floki.find(rows, "td")
    end

    test "renders table foot" do
      assigns = %{}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          on_sort={JS.push("sort")}
          id="user-table"
          items={[%{name: "George"}]}
          meta={%AshPagify.Meta{ash_pagify: %AshPagify{}}}
        >
          <:col :let={post} label="Name" field={:name}><%= post.name %></:col>
          <:foot>
            <tr>
              <td>snap</td>
            </tr>
          </:foot>
        </AshPagify.Components.table>
        """)

      assert [
               {"table", _,
                [
                  {"thead", _, _},
                  {"tbody", _, _},
                  {"tfoot", [], [{"tr", [], [{"td", [], ["snap"]}]}]}
                ]}
             ] = html
    end

    test "renders colgroup" do
      assigns = %{}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          on_sort={JS.push("sort")}
          id="user-table"
          items={[%{name: "George", surname: "Floyd", age: 8}]}
          meta={%AshPagify.Meta{ash_pagify: %AshPagify{}}}
        >
          <:col :let={post} label="Name" field={:name} col_style="width: 60%;">
            <%= post.name %>
          </:col>
          <:col :let={post} label="Surname" field={:surname}>
            <%= post.surname %>
          </:col>
          <:col :let={post} label="Age" field={:age} col_class="some-col-class">
            <%= post.age %>
          </:col>
        </AshPagify.Components.table>
        """)

      assert [
               {"table", _,
                [
                  {"colgroup", _,
                   [
                     {"col", [{"style", "width: 60%;"}], _},
                     {"col", [], _},
                     {"col", [{"class", "some-col-class"}], _}
                   ]},
                  {"thead", _, _},
                  {"tbody", _, _}
                ]}
             ] = html
    end

    test "does not render a colgroup if no style attribute is set" do
      assigns = %{}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          path="/posts"
          items={[%{name: "George", age: 8}]}
          meta={%AshPagify.Meta{ash_pagify: %AshPagify{}}}
        >
          <:col :let={post} label="Name" field={:name}><%= post.name %></:col>
          <:col :let={post} label="Age" field={:age}><%= post.age %></:col>
        </AshPagify.Components.table>
        """)

      assert [
               {"table", _,
                [
                  {"thead", _, _},
                  {"tbody", _, _}
                ]}
             ] = html
    end

    test "renders colgroup on action col" do
      assigns = %{}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table
          on_sort={JS.push("sort")}
          id="user-table"
          items={[%{name: "George", id: 1}]}
          meta={%AshPagify.Meta{ash_pagify: %AshPagify{}}}
        >
          <:col :let={post} label="Name" field={:name} col_style="width: 60%;">
            <%= post.name %>
          </:col>
          <:action :let={post} col_style="width: 40%;">
            <.link navigate={"/show/post/#{post.name}"}>
              Show Pet
            </.link>
          </:action>
        </AshPagify.Components.table>
        """)

      assert [
               {"table", _,
                [
                  {"colgroup", _,
                   [
                     {"col", [{"style", "width: 60%;"}], _},
                     {"col", [{"style", "width: 40%;"}], _}
                   ]},
                  {"thead", _, _},
                  {"tbody", _, _}
                ]}
             ] = html
    end

    test "doesn't render colgroup on action col if no style attribute is set" do
      assigns = %{meta: %AshPagify.Meta{ash_pagify: %AshPagify{}}}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table path="/posts" items={[%{}]} meta={@meta}>
          <:col></:col>
          <:action></:action>
        </AshPagify.Components.table>
        """)

      assert [
               {"table", _,
                [
                  {"thead", _, _},
                  {"tbody", _, _}
                ]}
             ] = html
    end

    test "renders caption text" do
      assert [
               {"table", [{"id", "some_table"}, {"class", "some-table"}],
                [
                  {"caption", [], ["some caption"]},
                  {"thead", _, _},
                  {"tbody", _, _}
                ]}
             ] = render_table(%{caption_text: "some caption"})
    end

    test "renders caption slot" do
      assigns = %{meta: %AshPagify.Meta{ash_pagify: %AshPagify{}}}

      html =
        parse_heex(~H"""
        <AshPagify.Components.table path="/posts" items={[%{}]} meta={@meta}>
          <:caption>
            <h1>Some caption</h1>
          </:caption>
          <:col></:col>
          <:action></:action>
        </AshPagify.Components.table>
        """)

      assert [
               {"table", _,
                [
                  {"caption", [], [{"h1", [], ["Some caption"]}]},
                  {"thead", _, _},
                  {"tbody", _, _}
                ]}
             ] = html
    end

    test "does not render table foot if option is not set" do
      html = render_table(%{})

      assert [
               {"table", [{"id", "some_table"}, {"class", "some-table"}], [{"thead", _, _}, {"tbody", _, _}]}
             ] = html
    end

    test "renders simple table if no meta is passed" do
      html = render_table(%{})

      assert [
               {"table", [{"id", "some_table"}, {"class", "some-table"}], [{"thead", _, _}, {"tbody", _, _}]}
             ] = html
    end

    test "raises if neither path nor on_sort are passed" do
      assert_raise PathOrJSError,
                   fn ->
                     render_component(&table/1,
                       __changed__: nil,
                       col: fn _ -> nil end,
                       items: [%{name: "George"}],
                       meta: %AshPagify.Meta{ash_pagify: %AshPagify{}}
                     )
                   end
    end

    test "does not crash if meta has errors" do
      {:error, meta} = AshPagify.validate(Post, %{offset: -1})
      render_table(%{meta: meta})
    end
  end

  describe "to_query/2" do
    test "does not add empty values" do
      refute %AshPagify{limit: nil} |> to_query() |> Keyword.has_key?(:limit)
      refute %AshPagify{order_by: []} |> to_query() |> Keyword.has_key?(:order_by)
      refute %AshPagify{filters: %{}} |> to_query() |> Keyword.has_key?(:filters)
      refute %AshPagify{filter_form: %{}} |> to_query() |> Keyword.has_key?(:filter_form)
      refute %AshPagify{scopes: %{}} |> to_query() |> Keyword.has_key?(:scopes)
      refute %AshPagify{search: %{}} |> to_query() |> Keyword.has_key?(:search)
    end

    test "does not add params for first page/offset" do
      refute %AshPagify{offset: 0} |> to_query() |> Keyword.has_key?(:offset)
    end

    test "does not add limit/page_size if it matches default" do
      opts = [default_limit: 20]

      assert %AshPagify{limit: 10}
             |> to_query(opts)
             |> Keyword.has_key?(:limit)

      refute %AshPagify{limit: 20}
             |> to_query(opts)
             |> Keyword.has_key?(:limit)
    end

    test "does not add order params if they match the default" do
      opts = [
        default_order: [id: :asc]
      ]

      # order_by does not match default
      query =
        to_query(
          %AshPagify{order_by: [name: :asc]},
          opts
        )

      assert Keyword.has_key?(query, :order_by)

      # order_by matches default
      query =
        to_query(
          %AshPagify{order_by: [id: :asc]},
          opts
        )

      refute Keyword.has_key?(query, :order_by)
    end

    test "does not add scopes params if they match the default" do
      opts = [
        default_scopes: %{status: :active}
      ]

      # scopes does not match default
      query =
        to_query(
          %AshPagify{scopes: %{status: :inactive}},
          opts
        )

      assert Keyword.has_key?(query, :scopes)

      # scopes matches default
      query =
        to_query(
          %AshPagify{scopes: %{status: :active}},
          opts
        )

      refute Keyword.has_key?(query, :scopes)
    end
  end

  describe "build_path/3" do
    test "gets the for option from the meta struct to retrieve defaults" do
      meta = %AshPagify.Meta{resource: Post, ash_pagify: %AshPagify{limit: 21}}
      assert build_path("/posts", meta) == "/posts?limit=21"

      meta = %AshPagify.Meta{resource: Post, ash_pagify: %AshPagify{limit: 15}}
      assert build_path("/posts", meta) == "/posts"
    end
  end

  defp custom_no_results_content do
    assigns = %{}

    ~H"""
    <div>Nothing!</div>
    """
  end

  defp custom_loading_content do
    assigns = %{}

    ~H"""
    <div>It's loading!</div>
    """
  end

  defp custom_error_content do
    assigns = %{}

    ~H"""
    <div>Crap!</div>
    """
  end
end
