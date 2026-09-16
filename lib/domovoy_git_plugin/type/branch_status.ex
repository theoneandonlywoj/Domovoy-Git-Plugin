defmodule DomovoyGitPlugin.Type.BranchStatus do
  @moduledoc """
  `DomovoyCore.Type` for the position of a branch and the state of the working
  tree, in one value.

  The raw value holds the branch that is checked out, the upstream branch, and
  the porcelain status entries. `upstream_branch` is `nil` when the branch has
  no upstream. A new branch normally has no upstream. Therefore `nil` is a
  correct state and not a failure.

  The pre-commit step, the pre-push step and the pull-request step all read this
  value. Thus they ask Git one time and not three times.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{
      ...>   current_branch: "main",
      ...>   upstream_branch: "origin/main",
      ...>   status: [%{path: "lib/a.ex", code: " M", index: :unmodified, worktree: :modified}]
      ...> }
      iex> {:ok, document} = DomovoyGitPlugin.Type.BranchStatus.dump(state)
      iex> document["current_branch"]
      "main"
      iex> DomovoyGitPlugin.Type.BranchStatus.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  alias DomovoyGitPlugin.Type.StatusEntries, as: StatusEntriesType

  defguardp is_branch_status(current_branch, upstream_branch, status)
            when is_binary(current_branch) and current_branch != "" and
                   (is_binary(upstream_branch) or is_nil(upstream_branch)) and is_list(status)

  @typedoc "A branch, its upstream, and the working tree status beneath it."
  @type state() :: %{
          current_branch: String.t(),
          upstream_branch: String.t() | nil,
          status: [StatusEntriesType.entry()]
        }

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(
        %{current_branch: current_branch, upstream_branch: upstream_branch, status: status} =
          state,
        _metadata
      )
      when is_branch_status(current_branch, upstream_branch, status) do
    {:ok, state}
  end

  def cast(_raw, _metadata), do: :error

  @keys [:current_branch, :upstream_branch, :status]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(%{"status" => status} = document) do
    with {:ok, status} <- StatusEntriesType.load(status) do
      document |> DomovoyCore.Type.atom_keys(@keys) |> Map.put(:status, status) |> cast()
    end
  end

  def load(_document), do: :error
end
