defmodule AshPagify.Factory.Registry do
  @moduledoc false
  use Ash.Registry

  entries do
    entry AshPagify.Factory.Post
    entry AshPagify.Factory.Comment
    entry AshPagify.Factory.User
  end
end
