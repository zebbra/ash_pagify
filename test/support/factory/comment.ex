defmodule AshPagify.Factory.Comment do
  @moduledoc false
  use Ash.Resource,
    data_layer: Ash.DataLayer.Ets,
    api: AshPagify.Factory.Api,
    extensions: [AshUUID]

  use AshPagify.Tsearch, only: [:full_text_search]

  require Ash.Query

  @full_text_search [
    prefix: false,
    any_word: true,
    tsvector_column: Ash.Query.expr(custom_tsvector)
  ]
  def full_text_search, do: @full_text_search

  ets do
    private? true
  end

  attributes do
    uuid_attribute :id
    attribute :body, :string, allow_nil?: false
    attribute :text, :string
  end

  relationships do
    belongs_to :post, AshPagify.Factory.Post do
      allow_nil? false
    end
  end

  calculations do
    calculate :tsquery,
              AshPostgres.Tsquery,
              expr(fragment("to_tsquery('simple', unaccent(?))", ^arg(:search))) do
      argument :search, :string, allow_expr?: true, allow_nil?: false
    end

    calculate :custom_tsvector,
              AshPostgres.Tsvector,
              expr(
                fragment(
                  "setweight(to_tsvector('english', unaccent(coalesce(?, ''))), 'A') || setweight(to_tsvector('english', unaccent(coalesce(?, ''))), 'B')",
                  body,
                  text
                )
              )
  end

  preparations do
    prepare build(sort: [id: :asc])
    prepare AshPagify.Factory.Preparations.Sort
  end

  actions do
    defaults [:create]

    read :read do
      primary? true
      argument :sort, :string, allow_nil?: true
      pagination offset?: true, countable: true, required?: false
    end

    read :by_post do
      argument :post_id, :string, allow_nil?: false
      pagination offset?: true, countable: true, required?: false

      filter expr(post_id == ^arg(:post_id))
    end
  end

  code_interface do
    define_for AshPagify.Factory.Api
    define :read
    define :by_post, args: [:post_id]
    define :create
  end
end
