defmodule DomovoyGitPlugin.Type.WorktreeDiff do
  @moduledoc """
  `DomovoyCore.Type` for everything that a worktree changed against its base
  branch.

  The raw value joins the identity of the worktree with the parsed files. The
  identity is the name, the path, the branch and the base branch of the
  comparison. Therefore a consumer knows what it reads and does not need a
  second lookup.

  A node that wants the same information as Markdown declares
  `DomovoyCore.Type.String` and sets `metadata["format"]` to `:md`. See
  `DomovoyGitPlugin.Runner.WorktreeDiff`.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{
      ...>   worktree_name: "bro-30",
      ...>   path: "/repo/.worktrees/bro-30",
      ...>   branch: "bro-30-stages",
      ...>   base_branch: "main",
      ...>   files: [%{file: "lib/a.ex", hunks: []}]
      ...> }
      iex> {:ok, document} = DomovoyGitPlugin.Type.WorktreeDiff.dump(state)
      iex> document["base_branch"]
      "main"
      iex> DomovoyGitPlugin.Type.WorktreeDiff.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  alias DomovoyGitPlugin.Capabilities.DiffParser
  alias DomovoyGitPlugin.Type.Diff, as: DiffType

  defguardp is_worktree_diff(worktree_name, path, branch, base_branch, files)
            when is_binary(worktree_name) and worktree_name != "" and is_binary(path) and
                   (is_binary(branch) or is_nil(branch)) and is_binary(base_branch) and
                   base_branch != "" and is_list(files)

  @typedoc "A worktree's identity together with what it changed."
  @type state() :: %{
          worktree_name: String.t(),
          path: String.t(),
          branch: String.t() | nil,
          base_branch: String.t(),
          files: [DiffParser.file_diff()]
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
          base_branch: base_branch,
          files: files
        } = state,
        _metadata
      )
      when is_worktree_diff(worktree_name, path, branch, base_branch, files) do
    {:ok, state}
  end

  def cast(_raw, _metadata), do: :error

  @keys [:worktree_name, :path, :branch, :base_branch, :files]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(%{"files" => files} = document) do
    with {:ok, files} <- DiffType.load(files) do
      document |> DomovoyCore.Type.atom_keys(@keys) |> Map.put(:files, files) |> cast()
    end
  end

  def load(_document), do: :error
end
