defmodule AshPagify.Factory.User do
  @moduledoc false
  use Ash.Resource,
    data_layer: Ash.DataLayer.Ets,
    api: AshPagify.Factory.Api,
    extensions: [AshUUID]

  ets do
    private? true
  end

  attributes do
    uuid_attribute :id
    attribute :name, :string, allow_nil?: false
    attribute :email, :string, allow_nil?: false
    attribute :age, :integer
  end

  preparations do
    prepare build(sort: [id: :asc])
    prepare AshPagify.Factory.Preparations.Sort
  end

  actions do
    defaults [:create, :read, :update, :destroy]
  end

  code_interface do
    define_for AshPagify.Factory.Api
    define :read
    define :create
    define :update
    define :destroy
  end
end
