defmodule AshPagifyTest do
  @moduledoc false
  use ExUnit.Case

  import Assertions

  alias Ash.Error.Query.InvalidLimit
  alias Ash.Error.Query.NoSuchField
  alias Ash.Page.Offset
  alias AshPagify.Error.Query.InvalidParamsError
  alias AshPagify.Error.Query.SearchNotImplemented
  alias AshPagify.Factory.Comment
  alias AshPagify.Factory.Post
  alias AshPagify.Factory.User
  alias AshPagify.Meta

  require Ash.Expr
  require Ash.Query

  doctest AshPagify, import: true

  setup do
    posts = [
      %{name: "Post 2", comments: ["Second", "Third", "Fourth", "Another"]},
      %{name: "Post 1", author: "John", comments: ["First", "Second"]},
      %{name: "Post 3", author: "Doe", comments: ["Second", "Third", "Another"]}
    ]

    Ash.bulk_create(posts, Post, :create)
    :ok
  end

  describe "ordering" do
    test "orders by name :asc" do
      ash_pagify = %AshPagify{order_by: :name}
      assert_post_names(ash_pagify, ["Post 1", "Post 2", "Post 3"])
    end

    test "orders by name :desc" do
      ash_pagify = %AshPagify{order_by: {:name, :desc}}
      assert_post_names(ash_pagify, ["Post 3", "Post 2", "Post 1"])
    end

    test "orders by author :asc_nils_first" do
      ash_pagify = %AshPagify{order_by: {:author, :asc_nils_first}}
      assert_post_names(ash_pagify, ["Post 2", "Post 3", "Post 1"])
    end

    test "orders by author :desc_nils_last" do
      ash_pagify = %AshPagify{order_by: {:author, :desc_nils_last}}
      assert_post_names(ash_pagify, ["Post 1", "Post 3", "Post 2"])
    end

    test "orders by calculation" do
      ash_pagify = %AshPagify{order_by: :comments_count}
      assert_post_names(ash_pagify, ["Post 1", "Post 3", "Post 2"])
    end

    test "orders by calculation :desc" do
      ash_pagify = %AshPagify{order_by: {:comments_count, :desc}}
      assert_post_names(ash_pagify, ["Post 2", "Post 3", "Post 1"])
    end

    test "orders by multiple fields" do
      ash_pagify = %AshPagify{order_by: [{:name, :asc}, {:comments_count, :desc}]}
      assert_post_names(ash_pagify, ["Post 1", "Post 2", "Post 3"])
    end
  end

  describe "filtering" do
    test "applies 'is_nil' filter" do
      ash_pagify = %AshPagify{filters: %{"author" => %{"is_nil" => true}}, order_by: :name}
      assert_post_names(ash_pagify, ["Post 2"])
    end

    test "applies `equals` filter" do
      ash_pagify = %AshPagify{filters: %{"name" => %{"equals" => "Post 1"}}, order_by: :name}
      assert_post_names(ash_pagify, ["Post 1"])
    end

    test "applies equality '==' filter" do
      ash_pagify = %AshPagify{filters: %{"name" => %{"==" => "Post 1"}}, order_by: :name}
      assert_post_names(ash_pagify, ["Post 1"])
    end

    test "applies inherit equality filter" do
      ash_pagify = %AshPagify{filters: %{"author" => "John"}, order_by: :name}
      assert_post_names(ash_pagify, ["Post 1"])
    end

    test "applies inequality 'not_equals' filter" do
      ash_pagify = %AshPagify{filters: %{"author" => %{"not_equals" => "John"}}, order_by: :name}
      assert_post_names(ash_pagify, ["Post 3"])
    end

    test "applies inequality '!=' filter" do
      ash_pagify = %AshPagify{filters: %{"author" => %{"!=" => "John"}}, order_by: :name}
      assert_post_names(ash_pagify, ["Post 3"])
    end

    test "applies greater than 'gt' filter" do
      ash_pagify = %AshPagify{filters: %{"comments_count" => %{"gt" => 2}}, order_by: :name}
      assert_post_names(ash_pagify, ["Post 2", "Post 3"])
    end

    test "applies greater than '>' filter" do
      ash_pagify = %AshPagify{filters: %{"comments_count" => %{">" => 2}}, order_by: :name}
      assert_post_names(ash_pagify, ["Post 2", "Post 3"])
    end

    test "applies greater than or equal 'gte' filter" do
      ash_pagify = %AshPagify{filters: %{"comments_count" => %{"gte" => 2}}, order_by: :name}
      assert_post_names(ash_pagify, ["Post 1", "Post 2", "Post 3"])
    end

    test "applies greater than or equal '>=' filter" do
      ash_pagify = %AshPagify{filters: %{"comments_count" => %{">=" => 2}}, order_by: :name}
      assert_post_names(ash_pagify, ["Post 1", "Post 2", "Post 3"])
    end

    test "applies less than 'lt' filter" do
      ash_pagify = %AshPagify{filters: %{"comments_count" => %{"lt" => 3}}, order_by: :name}
      assert_post_names(ash_pagify, ["Post 1"])
    end

    test "applies less than '<' filter" do
      ash_pagify = %AshPagify{filters: %{"comments_count" => %{"<" => 3}}, order_by: :name}
      assert_post_names(ash_pagify, ["Post 1"])
    end

    test "applies less than or equal 'lte' filter" do
      ash_pagify = %AshPagify{filters: %{"comments_count" => %{"lte" => 3}}, order_by: :name}
      assert_post_names(ash_pagify, ["Post 1", "Post 3"])
    end

    test "applies less than or equal '<=' filter" do
      ash_pagify = %AshPagify{filters: %{"comments_count" => %{"<=" => 3}}, order_by: :name}
      assert_post_names(ash_pagify, ["Post 1", "Post 3"])
    end

    test "applies and filter" do
      ash_pagify = %AshPagify{
        filters: %{"and" => [%{"author" => "John"}, %{"comments_count" => %{"gt" => 1}}]},
        order_by: :name
      }

      assert_post_names(ash_pagify, ["Post 1"])
    end

    test "applies inherit and filter" do
      ash_pagify = %AshPagify{
        filters: %{
          "author" => "John",
          "comments_count" => %{"gt" => 1}
        },
        order_by: :name
      }

      assert_post_names(ash_pagify, ["Post 1"])
    end

    test "applies or filter" do
      ash_pagify = %AshPagify{
        filters: %{"or" => [%{"author" => "John"}, %{"comments_count" => %{"gt" => 3}}]},
        order_by: :name
      }

      assert_post_names(ash_pagify, ["Post 1", "Post 2"])
    end

    test "applies nested 'or' and 'and' filter" do
      ash_pagify = %AshPagify{
        filters: %{
          "or" => [
            %{"author" => "John"},
            %{
              "and" => [
                %{"comments_count" => %{"gt" => 2}},
                %{"name" => %{"in" => ["Post 2", "Post 3"]}}
              ]
            }
          ]
        },
        order_by: :name
      }

      assert_post_names(ash_pagify, ["Post 1", "Post 2", "Post 3"])
    end

    test "filters by relation attribute" do
      ash_pagify = %AshPagify{
        filters: %{"comments" => %{"body" => "First"}},
        order_by: :name
      }

      assert_post_names(ash_pagify, ["Post 1"])
    end
  end

  describe "offset pagination" do
    test "pagination with limit" do
      ash_pagify = %AshPagify{limit: 10, order_by: :name}
      assert_post_names(ash_pagify, ["Post 1", "Post 2", "Post 3"])
      assert_page_opts(ash_pagify, [limit: 10, offset: 0, count: true], [])
    end

    test "pagination with limit and offset" do
      ash_pagify = %AshPagify{limit: 2, offset: 1, order_by: :name}
      assert_post_names(ash_pagify, ["Post 2", "Post 3"])
      assert_page_opts(ash_pagify, [limit: 2, offset: 1, count: true], [])
    end

    test "pagination with disabled count" do
      ash_pagify = %AshPagify{limit: 2, offset: 1, order_by: :name}
      assert_post_names(ash_pagify, ["Post 2", "Post 3"], page: [count: false])
      assert_page_opts(ash_pagify, [limit: 2, offset: 1, count: false], page: [count: false])
    end

    test "pagination with default limit from resource" do
      ash_pagify = %AshPagify{order_by: :name}
      assert_post_names(ash_pagify, ["Post 1", "Post 2", "Post 3"])
      assert_page_opts(ash_pagify, [limit: 15, offset: 0, count: true], [])
    end

    test "pagination with default limit from resource and offset" do
      ash_pagify = %AshPagify{offset: 1, order_by: :name}
      assert_post_names(ash_pagify, ["Post 2", "Post 3"])
      assert_page_opts(ash_pagify, [limit: 15, offset: 1, count: true], [])
    end

    test "pagination with default limit from resource and disabled count" do
      ash_pagify = %AshPagify{order_by: :name}
      assert_post_names(ash_pagify, ["Post 1", "Post 2", "Post 3"], page: [count: false])
      assert_page_opts(ash_pagify, [limit: 15, offset: 0, count: false], page: [count: false])
    end

    test "pagination with default limit from resource and offset and disabled count" do
      ash_pagify = %AshPagify{offset: 1, order_by: :name}
      assert_post_names(ash_pagify, ["Post 2", "Post 3"], page: [count: false])
      assert_page_opts(ash_pagify, [limit: 15, offset: 1, count: false], page: [count: false])
    end

    test "pagination with default limit from ash_pagify" do
      ash_pagify = %AshPagify{order_by: :body}

      assert_comment_names(ash_pagify, [
        "Another",
        "Another",
        "First",
        "Fourth",
        "Second",
        "Second",
        "Second",
        "Third",
        "Third"
      ])

      assert_comment_page_opts(ash_pagify, [limit: 25, offset: 0, count: true], [])
    end
  end

  describe "query/2" do
    test "uses default resource order_by if no order_by is provided" do
      ash_pagify = %AshPagify{}
      query = Ash.Query.new(Post)
      assert AshPagify.query(query, ash_pagify) == %Ash.Query{resource: AshPagify.Factory.Post}
    end

    test "applies ts_rank order if search is provided and no order_by is provided" do
      ash_pagify = %AshPagify{search: "Post 1"}
      query = Ash.Query.new(Post)

      tsvector_expr = AshPagify.Tsearch.tsvector()
      tsquery_str = AshPagify.Tsearch.tsquery("Post 1")
      tsquery_expr = Ash.Expr.expr(tsquery(search: ^tsquery_str))

      assert AshPagify.query(query, ash_pagify) == %Ash.Query{
               resource: AshPagify.Factory.Post,
               filter:
                 Ash.Query.filter(
                   Post,
                   full_text_search(tsvector: ^tsvector_expr, tsquery: ^tsquery_expr)
                 ).filter,
               sort:
                 Ash.Query.sort(Post,
                   full_text_search_rank: {%{tsvector: tsvector_expr, tsquery: tsquery_expr}, :desc}
                 ).sort
             }
    end

    test "applies order_by and not ts_rank if search and order_by is provided" do
      ash_pagify = %AshPagify{search: "Post 1", order_by: :name}
      query = Ash.Query.new(Post)

      tsvector_expr = AshPagify.Tsearch.tsvector()
      tsquery_str = AshPagify.Tsearch.tsquery("Post 1")
      tsquery_expr = Ash.Expr.expr(tsquery(search: ^tsquery_str))

      assert AshPagify.query(query, ash_pagify) == %Ash.Query{
               resource: AshPagify.Factory.Post,
               filter:
                 Ash.Query.filter(
                   Post,
                   full_text_search(tsvector: ^tsvector_expr, tsquery: ^tsquery_expr)
                 ).filter,
               sort: Ash.Query.sort(Post, name: :asc).sort
             }
    end
  end

  describe "all/4" do
    test "returns all matching posts" do
      ash_pagify = %AshPagify{
        limit: 2,
        offset: 2,
        order_by: :name,
        filters: %{"name" => %{"in" => ["Post 1", "Post 2", "Post 3"]}}
      }

      assert_post_names(ash_pagify, ["Post 3"])
    end
  end

  describe "count/2" do
    test "returns count of matching entries" do
      ash_pagify = %AshPagify{
        limit: 2,
        offset: 2,
        order_by: [:age],
        filters: %{comments_count: %{lte: 3}}
      }

      assert AshPagify.count(Post, ash_pagify) == 2
    end

    test "allows overriding query" do
      ash_pagify = %AshPagify{
        limit: 2,
        offset: 2,
        order_by: [:age],
        filters: %{comments_count: %{lte: 3}}
      }

      # default query
      assert AshPagify.count(Post, ash_pagify) == 2

      # custom count query
      assert AshPagify.count(
               Post,
               ash_pagify,
               count_query: Ash.Query.filter_input(Post, %{name: "Post 2"})
             ) == 1
    end

    test "allows overriding the count itself" do
      ash_pagify = %AshPagify{
        limit: 2,
        offset: 2,
        order_by: [:age],
        filters: %{comments_count: %{lte: 3}}
      }

      # default query
      assert AshPagify.count(Post, ash_pagify) == 2

      # custom count
      assert AshPagify.count(Post, ash_pagify, count: 6) == 6
    end
  end

  describe "meta/3" do
    test "returns the meta information for a query with limit/offset" do
      ash_pagify = %AshPagify{limit: 3, offset: 0, order_by: :name}
      page = AshPagify.all(Post, ash_pagify)
      meta = AshPagify.meta(page, ash_pagify)

      assert meta == %Meta{
               current_limit: 3,
               current_offset: 0,
               current_page: 1,
               default_scopes: %{status: :all},
               errors: [],
               has_next_page?: false,
               has_previous_page?: false,
               next_offset: nil,
               opts: [],
               ash_pagify: %AshPagify{filters: nil, limit: 3, offset: 0, order_by: :name},
               params: %{},
               previous_offset: 0,
               resource: Post,
               total_count: 3,
               total_pages: 1
             }
    end

    test "returns the meta information for a query without limit" do
      ash_pagify = %AshPagify{}
      page = AshPagify.all(Post, ash_pagify)
      meta = AshPagify.meta(page, ash_pagify)

      assert meta == %Meta{
               current_limit: 15,
               current_offset: 0,
               current_page: 1,
               default_scopes: %{status: :all},
               errors: [],
               has_next_page?: false,
               has_previous_page?: false,
               next_offset: nil,
               opts: [],
               ash_pagify: %AshPagify{},
               params: %{},
               previous_offset: 0,
               resource: Post,
               total_count: 3,
               total_pages: 1
             }
    end

    test "rounds current page if offset is between pages" do
      ash_pagify = %AshPagify{limit: 2, offset: 1, order_by: :name}
      page = AshPagify.all(Post, ash_pagify)
      meta = AshPagify.meta(page, ash_pagify)

      assert meta == %Meta{
               current_limit: 2,
               current_offset: 1,
               current_page: 2,
               default_scopes: %{status: :all},
               errors: [],
               has_next_page?: false,
               has_previous_page?: true,
               next_offset: nil,
               opts: [],
               ash_pagify: %AshPagify{limit: 2, offset: 1, order_by: :name},
               params: %{},
               previous_offset: 0,
               resource: Post,
               total_count: 3,
               total_pages: 2
             }
    end

    test "current page shouldn't be greate than total page numbers" do
      ash_pagify = %AshPagify{limit: 2, offset: 3, order_by: :name}
      page = AshPagify.all(Post, ash_pagify)
      meta = AshPagify.meta(page, ash_pagify)

      assert meta == %Meta{
               current_limit: 2,
               current_offset: 3,
               current_page: 2,
               default_scopes: %{status: :all},
               errors: [],
               has_next_page?: false,
               has_previous_page?: true,
               next_offset: nil,
               opts: [],
               ash_pagify: %AshPagify{limit: 2, offset: 3, order_by: :name},
               params: %{},
               previous_offset: 1,
               resource: Post,
               total_count: 3,
               total_pages: 2
             }
    end

    test "sets has_previous_page? and has_next_page?" do
      ash_pagify = %AshPagify{limit: 1, offset: 0, order_by: :name}
      page = AshPagify.all(Post, ash_pagify)
      meta = AshPagify.meta(page, ash_pagify)

      assert meta.has_previous_page? == false
      assert meta.has_next_page? == true

      ash_pagify = %AshPagify{limit: 1, offset: 1, order_by: :name}
      page = AshPagify.all(Post, ash_pagify)
      meta = AshPagify.meta(page, ash_pagify)

      assert meta.has_previous_page? == true
      assert meta.has_next_page? == true

      ash_pagify = %AshPagify{limit: 1, offset: 2, order_by: :name}
      page = AshPagify.all(Post, ash_pagify)
      meta = AshPagify.meta(page, ash_pagify)

      assert meta.has_previous_page? == true
      assert meta.has_next_page? == false

      ash_pagify = %AshPagify{limit: 1, offset: 3, order_by: :name}
      page = AshPagify.all(Post, ash_pagify)
      meta = AshPagify.meta(page, ash_pagify)

      assert meta.has_previous_page? == true
      assert meta.has_next_page? == false

      ash_pagify = %AshPagify{limit: 1, offset: 4, order_by: :name}
      page = AshPagify.all(Post, ash_pagify)
      meta = AshPagify.meta(page, ash_pagify)

      assert meta.has_previous_page? == true
      assert meta.has_next_page? == false
    end

    test "sets options" do
      ash_pagify = %AshPagify{limit: 1, offset: 0, order_by: :name}
      page = AshPagify.all(Post, ash_pagify)
      meta = AshPagify.meta(page, ash_pagify)

      assert meta.opts == []

      opts = [page: [count: false]]
      ash_pagify = %AshPagify{limit: 1, offset: 0, order_by: :name}
      page = AshPagify.all(Post, ash_pagify, opts)
      meta = AshPagify.meta(page, ash_pagify, opts)

      assert meta.opts == opts
    end

    test "sets default scopes" do
      ash_pagify = %AshPagify{limit: 1, offset: 0, order_by: :name}

      opts =
        AshPagify.Misc.maybe_put_compiled_scopes(Post,
          scopes: %{
            role: [
              %{name: :user, filter: %{author: "Doe"}, default?: true}
            ]
          }
        )

      page = AshPagify.all(Post, ash_pagify, opts)
      meta = AshPagify.meta(page, ash_pagify, opts)

      assert meta.default_scopes == %{role: :user, status: :all}
      assert meta.opts == []
    end
  end

  describe "run/4" do
    test "returns data and meta data" do
      ash_pagify = %AshPagify{limit: 2, offset: 1, order_by: :name}
      {data, meta} = AshPagify.run(Post, ash_pagify)

      assert Enum.map(data, & &1.name) == ["Post 2", "Post 3"]

      assert meta == %Meta{
               current_limit: 2,
               current_offset: 1,
               current_page: 2,
               default_scopes: %{status: :all},
               errors: [],
               has_next_page?: false,
               has_previous_page?: true,
               next_offset: nil,
               opts: [],
               ash_pagify: %AshPagify{limit: 2, offset: 1, order_by: :name},
               params: %{},
               previous_offset: 0,
               resource: Post,
               total_count: 3,
               total_pages: 2
             }
    end
  end

  describe "validate_and_run/4" do
    test "returns error if ash_pagify is invalid" do
      ash_pagify = %AshPagify{limit: -1, filters: %{name: "Post 1", other: "John"}}

      {:error, %Meta{} = meta} =
        AshPagify.validate_and_run(Post, ash_pagify, replace_invalid_params?: true)

      assert meta.ash_pagify == %AshPagify{}

      assert inspect(meta.params) ==
               ~s"%{offset: 0, filters: #Ash.Filter<name == \"Post 1\">, limit: 15, scopes: %{status: :all}}"

      assert [%InvalidLimit{limit: -1}] = Keyword.get(meta.errors, :limit)
      assert [%NoSuchField{field: :other}] = Keyword.get(meta.errors, :filters)
    end

    test "returns error and original params if ash_pagify is invalid" do
      ash_pagify = %AshPagify{limit: -1, filters: %{name: "Post 1", other: "John"}}

      {:error, %Meta{} = meta} =
        AshPagify.validate_and_run(Post, ash_pagify)

      assert meta.ash_pagify == %AshPagify{}

      assert %{
               limit: -1,
               filters: %{name: "Post 1", other: "John"},
               offset: 0,
               scopes: %{status: :all}
             } == meta.params

      assert [%InvalidLimit{limit: -1}] = Keyword.get(meta.errors, :limit)
      assert [%NoSuchField{field: :other}] = Keyword.get(meta.errors, :filters)
    end

    test "returns data and meta data" do
      ash_pagify = %AshPagify{limit: 2, offset: 1, order_by: :name}
      {:ok, {data, meta}} = AshPagify.validate_and_run(Post, ash_pagify)

      assert Enum.map(data, & &1.name) == ["Post 2", "Post 3"]

      assert meta == %Meta{
               current_limit: 2,
               current_offset: 1,
               current_page: 2,
               default_scopes: %{status: :all},
               errors: [],
               has_next_page?: false,
               has_previous_page?: true,
               next_offset: nil,
               opts: [],
               ash_pagify: %AshPagify{
                 limit: 2,
                 offset: 1,
                 order_by: [name: :asc],
                 scopes: %{status: :all}
               },
               params: %{},
               previous_offset: 0,
               resource: Post,
               total_count: 3,
               total_pages: 2
             }
    end
  end

  describe "validate_and_run!/4" do
    test "raises if ash_pagify is invalid" do
      assert_raise InvalidParamsError, fn ->
        AshPagify.validate_and_run!(Post, %AshPagify{
          limit: -1,
          filters: %{name: "Post 1", other: "John"}
        })
      end
    end

    test "returns data and meta data" do
      ash_pagify = %{limit: 1, offset: 0, order_by: :name, filters: %{"name" => "Post 2"}}

      assert {[%Post{}],
              %AshPagify.Meta{
                current_limit: 1,
                current_offset: 0,
                current_page: 1,
                errors: [],
                has_next_page?: false,
                has_previous_page?: false,
                next_offset: nil,
                opts: [],
                ash_pagify: %AshPagify{},
                params: %{},
                previous_offset: 0,
                total_count: 1,
                total_pages: 1
              }} = AshPagify.validate_and_run!(Post, ash_pagify)
    end
  end

  describe "validate/1" do
    test "returns AshPagify struct" do
      assert AshPagify.validate(Post, %AshPagify{}) ==
               {:ok, %AshPagify{limit: 15, offset: 0, scopes: %{status: :all}}}

      assert AshPagify.validate(Post, %{}) ==
               {:ok, %AshPagify{limit: 15, offset: 0, scopes: %{status: :all}}}
    end

    test "returns error and replaced params if parameters are invalid" do
      assert {:error, %Meta{} = meta} =
               AshPagify.validate(Post, %{limit: -1, filters: %{name: "Post 1", other: "John"}},
                 replace_invalid_params?: true
               )

      assert meta.ash_pagify == %AshPagify{}

      %{limit: limit, offset: offset, filters: filters} = meta.params
      assert limit == 15
      assert offset == 0
      assert inspect(filters) == ~s"#Ash.Filter<name == \"Post 1\">"

      assert [%InvalidLimit{limit: -1}] = Keyword.get(meta.errors, :limit)
      assert [%NoSuchField{field: :other}] = Keyword.get(meta.errors, :filters)
    end

    test "returns error and original params if parameters are invalid" do
      assert {:error, %Meta{} = meta} =
               AshPagify.validate(
                 Post,
                 %AshPagify{limit: -1, filters: %{name: "Post 1", other: "John"}}
               )

      assert meta.ash_pagify == %AshPagify{}

      assert %{
               limit: -1,
               filters: %{name: "Post 1", other: "John"},
               offset: 0,
               scopes: %{status: :all}
             } == meta.params

      assert [%InvalidLimit{limit: -1}] = Keyword.get(meta.errors, :limit)
      assert [%NoSuchField{field: :other}] = Keyword.get(meta.errors, :filters)
    end
  end

  describe "validate!/1" do
    test "returns AshPagify struct" do
      assert AshPagify.validate!(Post, %AshPagify{}) == %AshPagify{
               limit: 15,
               offset: 0,
               scopes: %{status: :all}
             }

      assert AshPagify.validate!(Post, %{}) == %AshPagify{
               limit: 15,
               offset: 0,
               scopes: %{status: :all}
             }
    end

    test "raises if params are invalid" do
      error =
        assert_raise InvalidParamsError, fn ->
          AshPagify.validate!(Post, %{limit: -1, filters: %{name: "Post 1", other: "John"}})
        end

      assert %{limit: -1, filters: %{name: "Post 1", other: "John"}} == error.params

      assert [%InvalidLimit{limit: -1}] = Keyword.get(error.errors, :limit)
      assert [%NoSuchField{field: :other}] = Keyword.get(error.errors, :filters)
    end
  end

  describe "get_index/2" do
    test "returns index of a field in the `AshPagify.order_by` list" do
      order_by = [name: :asc, age: :desc]
      assert AshPagify.get_index(order_by, :name) == 0
      assert AshPagify.get_index(order_by, :age) == 1
      assert AshPagify.get_index(order_by, :species) == nil

      # Or with a list of strings
      order_by = ["name", "age"]
      assert AshPagify.get_index(order_by, :name) == 0
      assert AshPagify.get_index(order_by, :age) == 1
      assert AshPagify.get_index(order_by, :species) == nil

      # Or with a tuple:
      order_by = {:name, :asc}
      assert AshPagify.get_index(order_by, :name) == nil
      assert AshPagify.get_index(order_by, :age) == nil

      # Or with a single string:
      order_by = "name"
      assert AshPagify.get_index(order_by, :name) == nil
      assert AshPagify.get_index(order_by, :age) == nil

      # Or with a single atom:
      order_by = :name
      assert AshPagify.get_index(order_by, :name) == nil
      assert AshPagify.get_index(order_by, :age) == nil

      # If the `order_by` parameter is `nil`, the function will return `nil`.
      assert AshPagify.get_index(nil, :name) == nil
    end
  end

  describe "push_order/3" do
    test "raises error if invalid directions option is passed" do
      for ash_pagify <- [%AshPagify{}, %AshPagify{order_by: [:name]}],
          directions <- [{:up, :down}, "up,down"] do
        assert_raise AshPagify.Error.Query.InvalidDirectionsError, fn ->
          AshPagify.push_order(ash_pagify, :name, directions: directions)
        end
      end
    end
  end

  describe "query_to_filters_map/2" do
    test "compiles scopes into filters" do
      assert %AshPagify{
               filters: %{"and" => [%{"author" => "John"}]},
               scopes: [role: :admin]
             } ==
               AshPagify.query_to_filters_map(Post, %AshPagify{
                 scopes: [{:role, :admin}]
               })
    end

    test "compiles filter_form into filters" do
      assert %AshPagify{
               filters: %{"and" => [%{"name" => %{"eq" => "Post 1"}}]},
               filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"}
             } ==
               AshPagify.query_to_filters_map(Post, %AshPagify{
                 filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"}
               })
    end

    test "compiles filters into filters" do
      assert %AshPagify{
               filters: %{"and" => [%{"author" => "Author 1"}]}
             } ==
               AshPagify.query_to_filters_map(Post, %AshPagify{
                 filters: %{author: "Author 1"}
               })
    end

    test "accounts for and base filter" do
      assert %AshPagify{
               filters: %{"and" => [%{"author" => "Author 1"}]}
             } ==
               AshPagify.query_to_filters_map(Post, %AshPagify{
                 filters: %{"and" => [%{author: "Author 1"}]}
               })
    end

    test "accounts for or base filter" do
      assert %AshPagify{
               filters: %{"or" => [%{"author" => "Author 1"}]}
             } ==
               AshPagify.query_to_filters_map(Post, %AshPagify{
                 filters: %{"or" => [%{author: "Author 1"}]}
               })
    end

    test "merges filters from scope, filter_form, and filters into filters" do
      assert %AshPagify{
               filters: %{
                 "and" => [
                   %{"comments_count" => %{"gt" => 2}},
                   %{"name" => %{"eq" => "Post 1"}},
                   %{"author" => "John"}
                 ]
               },
               filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"},
               scopes: [role: :admin]
             } ==
               AshPagify.query_to_filters_map(Post, %AshPagify{
                 filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"},
                 scopes: [{:role, :admin}],
                 filters: %{comments_count: %{gt: 2}}
               })
    end

    test "filter_form overrides filters" do
      assert %AshPagify{
               filters: %{
                 "and" => [
                   %{"name" => %{"eq" => "Post 2"}}
                 ]
               },
               filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 2"}
             } ==
               AshPagify.query_to_filters_map(Post, %AshPagify{
                 filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 2"},
                 filters: %{"and" => %{"name" => "Post 1"}}
               })
    end

    test "stores full-text search under __full_text_search" do
      assert %AshPagify{
               filters: %{
                 "__full_text_search" => %{
                   "search" => "Post 1"
                 }
               },
               search: "Post 1"
             } ==
               AshPagify.query_to_filters_map(
                 Post,
                 %AshPagify{
                   search: "Post 1"
                 }
               )
    end

    test "stores user provided full-text search opts alongside the search term under __full_text_search" do
      assert %AshPagify{
               filters: %{
                 "__full_text_search" => %{
                   "search" => "Post 1",
                   "any_word" => true,
                   "negation" => true,
                   "prefix" => true,
                   "tsvector" => "custom_tsvector"
                 }
               },
               search: "Post 1"
             } ==
               AshPagify.query_to_filters_map(
                 Post,
                 %AshPagify{
                   search: "Post 1"
                 },
                 full_text_search: [
                   negation: true,
                   prefix: true,
                   any_word: true,
                   tsvector: "custom_tsvector"
                 ]
               )
    end

    test "removes invalid full-text search opts" do
      assert %AshPagify{
               filters: %{
                 "__full_text_search" => %{
                   "search" => "Post 1",
                   "any_word" => true
                 }
               },
               search: "Post 1"
             } ==
               AshPagify.query_to_filters_map(
                 Post,
                 %AshPagify{
                   search: "Post 1"
                 },
                 full_text_search: [foo: :bar, any_word: true]
               )
    end

    test "stores full-text search under __full_text_search in combinatino with other filters" do
      assert %AshPagify{
               filters: %{
                 "and" => [
                   %{"comments_count" => %{"gt" => 2}},
                   %{"name" => %{"eq" => "Post 1"}},
                   %{"author" => "John"}
                 ],
                 "__full_text_search" => %{"search" => "Post 1"}
               },
               filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"},
               scopes: [role: :admin],
               search: "Post 1"
             } ==
               AshPagify.query_to_filters_map(
                 Post,
                 %AshPagify{
                   filter_form: %{"field" => "name", "operator" => "eq", "value" => "Post 1"},
                   scopes: [{:role, :admin}],
                   filters: %{comments_count: %{gt: 2}},
                   search: "Post 1"
                 }
               )
    end

    test "does not store full-text search under __full_text_search if disabled" do
      assert %AshPagify{
               filters: %{},
               search: "Post 1"
             } ==
               AshPagify.query_to_filters_map(
                 Post,
                 %AshPagify{
                   search: "Post 1"
                 },
                 include_full_text_search?: false
               )
    end

    test "does not raise and not store in case of invalid full-text search" do
      assert %{
               filters: %{},
               search: "User 1",
               errors: [
                 search: [
                   %SearchNotImplemented{resource: User}
                 ]
               ]
             } =
               AshPagify.query_to_filters_map(
                 User,
                 %AshPagify{
                   search: "User 1"
                 },
                 raise_on_invalid_search?: false
               )
    end

    test "raises and does not store in case of invalid full-text search" do
      assert_raise SearchNotImplemented, fn ->
        AshPagify.query_to_filters_map(
          User,
          %AshPagify{
            search: "Comment 1"
          }
        )
      end
    end

    test "scope overrides filters" do
      assert %AshPagify{
               filters: %{
                 "and" => [
                   %{"author" => "John"}
                 ]
               },
               scopes: [role: :admin]
             } ==
               AshPagify.query_to_filters_map(Post, %AshPagify{
                 filters: %{"author" => "Author 1"},
                 scopes: [{:role, :admin}]
               })
    end
  end

  describe "query_for_filters_map/2" do
    test "converts compiled filters to map" do
      assert AshPagify.query_for_filters_map(Post, %{"and" => [%{"name" => "foo"}]}) ==
               Ash.Query.filter(Post, %{name: "foo"})
    end

    test "does not include full_text_search if disabled" do
      assert AshPagify.query_for_filters_map(
               Post,
               %{"and" => [%{"name" => "foo"}], "__full_text_search" => "bar"},
               include_full_text_search?: false
             ) ==
               Ash.Query.filter(Post, %{name: "foo"})
    end

    test "includes full_text_search per default and orders by ts_rank if no order_by is provided" do
      assert_map_query_equals_full_text_search(
        %{"__full_text_search" => %{"search" => "bar"}},
        "bar:*"
      )
    end

    test "includes user provided search settings as well" do
      assert_map_query_equals_full_text_search(
        %{
          "__full_text_search" => %{
            "search" => "!bar blub",
            "any_word" => true,
            "negation" => false,
            "prefix" => false
          }
        },
        "!bar | blub"
      )
    end

    test "falls back to default tsvector if an invalid tsvector is stored" do
      assert_map_query_equals_full_text_search(
        %{
          "__full_text_search" => %{
            "search" => "bar",
            "tsvector" => "invalid_tsvector"
          }
        },
        "bar:*"
      )
    end

    test "does not include full_text_search if include_full_text_search? is true but none is provided" do
      assert AshPagify.query_for_filters_map(
               Post,
               %{"name" => "bar"}
             ) ==
               Ash.Query.filter(Post, name: "bar")
    end

    test "does not include full_text_search if none is configured and does not raise" do
      assert AshPagify.query_for_filters_map(
               User,
               %{"and" => [%{"name" => "foo"}], "__full_text_search" => %{"search" => "bar"}},
               raise_on_invalid_search?: false
             ) ==
               Ash.Query.filter(User, %{name: "foo"})
    end

    test "does not include full_text_search if none is configured and raises" do
      assert_raise SearchNotImplemented, fn ->
        AshPagify.query_for_filters_map(
          User,
          %{"and" => [%{"name" => "foo"}], "__full_text_search" => %{"search" => "bar"}}
        )
      end
    end
  end

  describe "extract_full_text_search/1" do
    test "extracts full_text_search from filters" do
      assert AshPagify.extract_full_text_search(%{"__full_text_search" => "bar"}) ==
               {%{}, "bar"}
    end

    test "does not extract full_text_search if none is provided" do
      assert AshPagify.extract_full_text_search(%{"name" => "bar"}) ==
               {%{"name" => "bar"}, nil}
    end

    test "extracts the full_text_search term from the and base filter with multiple entries" do
      assert AshPagify.extract_full_text_search(%{
               :foo => :bar,
               "and" => [%{"__full_text_search" => "bar"}, %{"name" => "foo"}],
               "or" => [%{"age" => "12"}]
             }) ==
               {%{:foo => :bar, "and" => [%{"name" => "foo"}], "or" => [%{"age" => "12"}]}, "bar"}
    end

    test "extracts the full_text_search term from the or base filter with multiple entries" do
      assert AshPagify.extract_full_text_search(%{
               :foo => :bar,
               "or" => [%{"__full_text_search" => "bar"}, %{"name" => "foo"}]
             }) ==
               {%{:foo => :bar, "or" => [%{"name" => "foo"}]}, "bar"}
    end
  end

  defp assert_map_query_equals_full_text_search(map_query, search) do
    tsvector_expr = AshPagify.Tsearch.tsvector()
    tsquery_expr = Ash.Expr.expr(tsquery(search: ^search))

    assert AshPagify.query_for_filters_map(Post, map_query) ==
             Post
             |> Ash.Query.filter(full_text_search(tsvector: ^tsvector_expr, tsquery: ^tsquery_expr))
             |> Ash.Query.sort(full_text_search_rank: {%{tsvector: tsvector_expr, tsquery: tsquery_expr}, :desc})
  end

  defp assert_post_names(ash_pagify, names, opts \\ []) do
    %Offset{results: posts} = AshPagify.all(Post, ash_pagify, opts)

    assert Enum.map(posts, & &1.name) == names
  end

  defp assert_page_opts(ash_pagify, expected, opts) do
    %Offset{rerun: {%Ash.Query{page: page}, _}} = AshPagify.all(Post, ash_pagify, opts)

    assert_lists_equal(expected, page)
  end

  defp assert_comment_names(ash_pagify, names, opts \\ []) do
    %Offset{results: comments} = AshPagify.all(Comment, ash_pagify, opts)

    assert Enum.map(comments, & &1.body) == names
  end

  defp assert_comment_page_opts(ash_pagify, expected, opts) do
    %Offset{rerun: {%Ash.Query{page: page}, _}} =
      AshPagify.all(Comment, ash_pagify, opts)

    assert_lists_equal(expected, page)
  end
end
