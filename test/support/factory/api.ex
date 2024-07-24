defmodule AshPagify.Factory.Api do
  @moduledoc false
  use Ash.Api

  resources do
    registry AshPagify.Factory.Registry
  end
end
