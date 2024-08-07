defmodule AshPagify.Guards do
  @moduledoc """
  Custom guards for the AshPagify library.
  """

  @valid_option_keys AshPagify.default_opts_keys() ++ [:default_order, :pagination, :table]

  @doc """
  Check if a given key is a valid `t:AshPagify.option/0` key.
  """
  @spec is_valid_option(Macro.t()) :: Macro.t()
  defguard is_valid_option(key) when key in @valid_option_keys
end
