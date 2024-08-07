defmodule AshPagify.Factory.Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    resource AshPagify.Factory.Comment
    resource AshPagify.Factory.Post
    resource AshPagify.Factory.User
  end
end
