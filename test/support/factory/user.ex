defmodule AshPagify.Factory.User do
  @moduledoc false
  use Ash.Resource,
    data_layer: Ash.DataLayer.Ets,
    domain: AshPagify.Factory.Domain,
    extensions: [AshUUID]

  ets do
    private? true
  end

  attributes do
    uuid_attribute :id, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :age, :integer, public?: true
  end

  preparations do
    prepare build(sort: [id: :asc])
    prepare AshPagify.Factory.Preparations.Sort
  end

  actions do
    default_accept :*
    defaults [:create, :read, :update, :destroy]
  end

  code_interface do
    define :read
    define :create
    define :update
    define :destroy
  end
end
