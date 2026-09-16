defmodule DomovoyGitPlugin.Type.Worktrees do
  @moduledoc """
  `DomovoyCore.Type` for the Git worktrees of a repository.

  The raw value holds the root of the repository and a flat list of paths.

  This shape is different from `DomovoyGitPlugin.Type.Worktree`. That type holds one
  full record for one worktree, with its branch and its base branch. This type
  holds only the paths, and it holds them for every worktree of the repository.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{repo_root: "/repo", paths: ["/repo", "/repo/.worktrees/bro-30"]}
      iex> {:ok, document} = DomovoyGitPlugin.Type.Worktrees.dump(state)
      iex> document
      %{"repo_root" => "/repo", "paths" => ["/repo", "/repo/.worktrees/bro-30"]}
      iex> DomovoyGitPlugin.Type.Worktrees.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @type state() :: %{repo_root: String.t(), paths: [String.t()]}

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{repo_root: repo_root, paths: paths} = state, _metadata)
      when is_binary(repo_root) and is_list(paths) do
    if Enum.all?(paths, &is_binary/1), do: {:ok, state}, else: :error
  end

  def cast(_raw, _metadata), do: :error

  @keys [:repo_root, :paths]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
