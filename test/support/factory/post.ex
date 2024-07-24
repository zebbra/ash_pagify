defmodule AshPagify.Factory.Post do
  @moduledoc false
  use Ash.Resource,
    data_layer: Ash.DataLayer.Ets,
    api: AshPagify.Factory.Api,
    extensions: [AshUUID]

  use AshPagify.Tsearch

  require Ash.Query

  @default_limit 15
  def default_limit, do: @default_limit

  @ash_pagify_scopes %{
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
  def ash_pagify_scopes, do: @ash_pagify_scopes

  def full_text_search do
    [
      tsvector_column: [
        custom_tsvector: Ash.Query.expr(custom_tsvector)
      ]
    ]
  end

  ets do
    private? true
  end

  attributes do
    uuid_attribute :id
    attribute :name, :string, allow_nil?: false
    attribute :title, :string
    attribute :text, :string
    attribute :author, :string
    attribute :age, :integer

    # allow sorting by inserted_at/updated_at
    timestamps(private?: false, writable?: false)
  end

  relationships do
    has_many :comments, AshPagify.Factory.Comment
  end

  calculations do
    calculate :tsvector,
              AshPostgres.Tsvector,
              expr(fragment("to_tsvector('simple', coalesce(?, ''))", title))

    calculate :custom_tsvector,
              AshPostgres.Tsvector,
              expr(
                fragment(
                  "setweight(to_tsvector('english', unaccent(coalesce(?, ''))), 'A') || setweight(to_tsvector('english', unaccent(coalesce(?, ''))), 'B')",
                  name,
                  text
                )
              )

    calculate :add_age, :integer, expr(fragment("age + ?", ^arg(:add))) do
      argument :add, :integer, allow_nil?: false
    end
  end

  aggregates do
    count :comments_count, :comments
  end

  preparations do
    prepare build(sort: [name: :asc])
    prepare AshPagify.Factory.Preparations.Sort
  end

  actions do
    read :read do
      primary? true
      argument :sort, :string, allow_nil?: true
      pagination offset?: true, default_limit: @default_limit, countable: true, required?: false
    end

    create :create do
      primary? true
      argument :comments, {:array, :string}, allow_nil?: true
      change manage_relationship(:comments, type: :create, value_is_key: :body)
    end
  end

  code_interface do
    define_for AshPagify.Factory.Api
    define :read
    define :create
  end
end
