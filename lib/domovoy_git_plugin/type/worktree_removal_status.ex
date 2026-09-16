defmodule DomovoyGitPlugin.Type.WorktreeRemovalStatus do
  @moduledoc """
  `DomovoyCore.Type` for the result of the removal of a managed worktree.

  The raw value names the worktree that the runner removed, the location of the
  worktree, the branch of the worktree, and whether the runner also deleted that
  branch. `removed?` is always `true`. A removal that fails gives a
  `DomovoyCore.Error`. It never gives a value that says that the removal did not
  occur.

  `branch_deleted?` is `false` in two conditions. The caller did not ask for the
  deletion of the branch. Or the worktree was detached and thus had no branch to
  delete.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{
      ...>   worktree_name: "bro-30",
      ...>   path: "/repo/.worktrees/bro-30",
      ...>   branch: "bro-30-stages",
      ...>   removed?: true,
      ...>   branch_deleted?: false
      ...> }
      iex> {:ok, document} = DomovoyGitPlugin.Type.WorktreeRemovalStatus.dump(state)
      iex> document["removed?"]
      true
      iex> DomovoyGitPlugin.Type.WorktreeRemovalStatus.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  defguardp is_removal(worktree_name, path, branch, branch_deleted?)
            when is_binary(worktree_name) and worktree_name != "" and is_binary(path) and
                   (is_binary(branch) or is_nil(branch)) and is_boolean(branch_deleted?)

  @typedoc "What was removed, and whether its branch went with it."
  @type state() :: %{
          worktree_name: String.t(),
          path: String.t(),
          branch: String.t() | nil,
          removed?: true,
          branch_deleted?: boolean()
        }

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(
        %{
          worktree_name: worktree_name,
          path: path,
          branch: branch,
          removed?: true,
          branch_deleted?: branch_deleted?
        } = state,
        _metadata
      )
      when is_removal(worktree_name, path, branch, branch_deleted?) do
    {:ok, state}
  end

  def cast(_raw, _metadata), do: :error

  @keys [:worktree_name, :path, :branch, :removed?, :branch_deleted?]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
