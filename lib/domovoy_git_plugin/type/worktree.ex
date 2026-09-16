defmodule DomovoyGitPlugin.Type.Worktree do
  @moduledoc """
  `DomovoyCore.Type` for the state of a managed Git worktree.

  The raw value holds the root of the repository, the name of the worktree, its
  path, its branch and its base branch. It also holds two flags. `exists?` says
  whether the worktree is on the disk. `created?` says whether this run made the
  worktree. A node that skipped the creation gives `exists?: true` and
  `created?: false`.

  A detached worktree gives `branch: nil`. A worktree that has no Domovoy record
  gives `base_branch: nil`.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{
      ...>   repo_root: "/repo",
      ...>   name: "bro-30",
      ...>   path: "/repo/.worktrees/bro-30",
      ...>   exists?: true,
      ...>   created?: false,
      ...>   branch: "bro-30-stages",
      ...>   base_branch: "main"
      ...> }
      iex> {:ok, document} = DomovoyGitPlugin.Type.Worktree.dump(state)
      iex> document["exists?"]
      true
      iex> DomovoyGitPlugin.Type.Worktree.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @type state() :: %{
          required(:repo_root) => String.t(),
          required(:name) => String.t(),
          required(:path) => String.t(),
          required(:exists?) => boolean(),
          required(:created?) => boolean(),
          required(:branch) => String.t() | nil,
          optional(:local_branch?) => boolean(),
          optional(:remote_branch?) => boolean(),
          optional(:base_branch) => String.t() | nil
        }

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(
        %{
          repo_root: repo_root,
          name: name,
          path: path,
          exists?: exists?,
          created?: created?,
          branch: branch
        } = state,
        _metadata
      )
      when is_binary(repo_root) and is_binary(name) and is_binary(path) and is_boolean(exists?) and
             is_boolean(created?) and (is_binary(branch) or is_nil(branch)) do
    {:ok, state}
  end

  def cast(_raw, _metadata), do: :error

  @keys [
    :repo_root,
    :name,
    :path,
    :exists?,
    :created?,
    :branch,
    :local_branch?,
    :remote_branch?,
    :base_branch
  ]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
