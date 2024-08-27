defmodule AshPagify.MiscTest do
  @moduledoc false

  use ExUnit.Case

  alias AshPagify.Factory.Post

  doctest AshPagify.Misc, import: true

  describe "stringify_keys/1" do
    test "converts maps with date values" do
      map = %{
        "and" => [
          %{
            "and" => [
              %{"eve_event_date" => %{"greater_than_or_equal" => ~D[2024-06-11]}},
              %{"eve_event_date" => %{"less_than_or_equal" => ~D[2024-07-11]}}
            ]
          }
        ]
      }

      assert AshPagify.Misc.stringify_keys(map) == map
    end
  end

  describe "get_option/3" do
    test "returns value from option list" do
      # sanity check
      default_limit = Post.ash_pagify_options().default_limit
      assert default_limit && default_limit != 40

      assert AshPagify.Misc.get_option(
               :default_limit,
               [default_limit: 40, for: Post],
               1
             ) == 40
    end

    test "falls back to resource option" do
      # sanity check
      assert default_limit = Post.ash_pagify_options().default_limit

      assert AshPagify.Misc.get_option(
               :default_limit,
               [for: Post],
               1
             ) == default_limit
    end

    test "falls back to default AshPagify value" do
      assert AshPagify.Misc.get_option(:default_limit, []) == 25
    end

    test "raises ArgumentError for invalid option" do
      assert_raise ArgumentError, fn ->
        AshPagify.Misc.get_option(:some_option, [])
      end
    end

    test "raises ArgumentError for invalid option with default value" do
      assert_raise ArgumentError, fn ->
        AshPagify.Misc.get_option(:some_option, [], 2)
      end
    end

    test "merges scopes" do
      # sanity check
      assert AshPagify.Misc.get_option(:scopes, [for: Post], %{}) ==
               Post.ash_pagify_options().scopes

      # with default value
      assert AshPagify.Misc.get_option(:scopes, [for: Post], %{
               role: [
                 %{name: :admin, filter: %{author: "John"}, default?: true}
               ]
             }) == %{
               role: [
                 %{name: :admin, filter: %{author: "John"}, default?: true},
                 %{name: :user, filter: %{author: "Doe"}}
               ],
               status: [
                 %{name: :all, filter: nil, default?: true},
                 %{name: :active, filter: %{age: %{lt: 10}}},
                 %{name: :inactive, filter: %{age: %{gte: 10}}}
               ]
             }

      # with opts scopes
      opts = [
        scopes: %{
          other: [
            %{name: :other, filter: %{name: "other"}}
          ],
          role: [
            %{name: :user, filter: %{name: "changed"}},
            %{name: :other, filter: %{name: "other"}}
          ],
          status: [
            %{name: :inactive, filter: %{age: %{gte: 10}}},
            %{name: :all, filter: nil, default?: true},
            %{name: :active, filter: %{age: %{lt: 10}}}
          ]
        },
        for: Post
      ]

      default = %{
        role: [
          %{name: :admin, filter: %{author: "John"}, default?: true}
        ]
      }

      assert AshPagify.Misc.get_option(:scopes, opts, default) == %{
               role: [
                 %{name: :admin, filter: %{author: "John"}, default?: true},
                 %{name: :user, filter: %{name: "changed"}},
                 %{name: :other, filter: %{name: "other"}}
               ],
               other: [
                 %{name: :other, filter: %{name: "other"}}
               ],
               status: [
                 %{name: :inactive, filter: %{age: %{gte: 10}}},
                 %{name: :all, filter: nil, default?: true},
                 %{name: :active, filter: %{age: %{lt: 10}}}
               ]
             }
    end
  end
end
