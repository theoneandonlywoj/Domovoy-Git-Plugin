defmodule DomovoyGitPlugin.Type.WorktreeRecords do
  @moduledoc """
  `DomovoyCore.Type` for the full worktree listing of a repository.

  The raw value holds one entry for each worktree. The main checkout is also an
  entry. The main checkout has `main?: true` and no `worktree_name`. It is not a
  managed worktree in `.worktrees/`. Every other entry takes its name from the
  last segment of its path.

  A detached worktree gives `branch: nil`. A worktree that a person made with
  `git worktree add` gives `base_branch: nil`.

  This shape is different from `DomovoyGitPlugin.Type.Worktrees`. That type holds
  only a repository root and a flat list of paths for the worktree workflow.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> records = [
      ...>   %{worktree_name: "main", path: "/repo", branch: "main", head: "abc123", base_branch: nil, main?: true}
      ...> ]
      iex> {:ok, document} = DomovoyGitPlugin.Type.WorktreeRecords.dump(records)
      iex> hd(document)["head"]
      "abc123"
      iex> DomovoyGitPlugin.Type.WorktreeRecords.load(document)
      {:ok, records}
  """

  use DomovoyCore.Type

  defguardp is_worktree(worktree_name, path, main?)
            when is_binary(path) and path != "" and is_boolean(main?) and
                   (is_binary(worktree_name) or is_nil(worktree_name))

  @typedoc "One worktree of a repository, as reported to a caller."
  @type worktree() :: %{
          worktree_name: String.t() | nil,
          path: String.t(),
          branch: String.t() | nil,
          head: String.t() | nil,
          base_branch: String.t() | nil,
          main?: boolean()
        }

  @impl Ecto.Type
  def type, do: {:array, :map}

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw_value, _metadata) when is_list(raw_value) do
    if Enum.all?(raw_value, &worktree?/1) do
      {:ok, raw_value}
    else
      :error
    end
  end

  def cast(_raw, _metadata), do: :error

  @spec worktree?(any()) :: boolean()
  defp worktree?(%{worktree_name: worktree_name, path: path, main?: main?})
       when is_worktree(worktree_name, path, main?),
       do: true

  defp worktree?(_other), do: false

  @worktree_keys [:worktree_name, :path, :branch, :head, :base_branch, :main?]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, [worktree()]} | :error
  def load(document) when is_list(document) do
    with {:ok, worktrees} <- DomovoyCore.Type.load_each(document, &load_worktree/1) do
      cast(worktrees)
    end
  end

  def load(_document), do: :error

  @spec load_worktree(document :: any()) :: {:ok, worktree()} | :error
  defp load_worktree(document) when is_map(document),
    do: {:ok, DomovoyCore.Type.atom_keys(document, @worktree_keys)}

  defp load_worktree(_document), do: :error
end
