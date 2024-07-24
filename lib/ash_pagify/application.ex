defmodule AshPagify.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [AshPagify.Repo]

    opts = [strategy: :one_for_one, name: Foo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
