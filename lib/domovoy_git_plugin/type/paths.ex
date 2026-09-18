defmodule DomovoyGitPlugin.Type.Paths do
  @moduledoc """
  `DomovoyCore.Type` for a list of repository paths.

  The raw value is a list of binaries. Each binary is one path argument for a
  Git command such as `git add --`. An empty list is a valid value of this type.
  Runners that must refuse an empty list do that in a validator, so the node
  does not start.

  ## Examples

      iex> DomovoyGitPlugin.Type.Paths.cast(["lib/a.ex", "README.md"])
      {:ok, ["lib/a.ex", "README.md"]}

      iex> DomovoyGitPlugin.Type.Paths.cast([])
      {:ok, []}

      iex> DomovoyGitPlugin.Type.Paths.cast("lib/a.ex")
      :error
  """

  use DomovoyCore.Type

  @impl Ecto.Type
  def type, do: {:array, :string}

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw_value, _metadata) when is_list(raw_value) do
    if Enum.all?(raw_value, &is_binary/1) do
      {:ok, raw_value}
    else
      :error
    end
  end

  def cast(_raw, _metadata), do: :error
end
