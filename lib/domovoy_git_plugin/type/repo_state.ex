defmodule DomovoyGitPlugin.Type.RepoState do
  @moduledoc """
  `DomovoyCore.Type` for a snapshot of one Git checkout.

  The raw value describes **this** checkout from `working_directory`. That
  directory may be the main worktree or a linked worktree. `path` is this
  checkout. `repo_root` is the main checkout. `base_branch` is the start ref
  that Domovoy recorded. It is `nil` on the main checkout and on an unmanaged
  worktree. It is not whatever the main checkout currently has checked out.

  `dirty?` is derived from `status`. The field stays so a graph node can bind a
  boolean without an extractor over the list. `conflicts` is `[]` when the
  index has no unmerged paths. That is success, not an error.

  The map is locked. Later slices fill the same keys. `dump/1` and `load/1`
  never grow required keys.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{
      ...>   path: "/repo",
      ...>   repo_root: "/repo",
      ...>   checkout: :main,
      ...>   worktree_name: nil,
      ...>   base_branch: nil,
      ...>   current_branch: "main",
      ...>   detached?: false,
      ...>   upstream_branch: "origin/main",
      ...>   ahead: 0,
      ...>   behind: 0,
      ...>   dirty?: false,
      ...>   operation: :idle,
      ...>   status: [],
      ...>   conflicts: []
      ...> }
      iex> {:ok, document} = DomovoyGitPlugin.Type.RepoState.dump(state)
      iex> document["checkout"]
      "main"
      iex> DomovoyGitPlugin.Type.RepoState.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  alias DomovoyGitPlugin.Type.Conflicts, as: ConflictsType
  alias DomovoyGitPlugin.Type.StatusEntries, as: StatusEntriesType

  @checkouts [:main, :worktree]
  @operations [:idle, :merging, :rebasing, :cherry_picking, :reverting]

  @typedoc "Whether this checkout is the main worktree or a linked worktree."
  @type checkout() :: :main | :worktree

  @typedoc """
  The in-progress Git operation of this checkout.

  Detection prefers rebase, then merge, then cherry-pick, then revert, when
  more than one Git state exists. A rebase counts through its state directory,
  since Git leaves `REBASE_HEAD` behind after a completed rebase.
  """
  @type operation() :: :idle | :merging | :rebasing | :cherry_picking | :reverting

  @typedoc "A snapshot of one checkout."
  @type state() :: %{
          path: String.t(),
          repo_root: String.t(),
          checkout: checkout(),
          worktree_name: String.t() | nil,
          base_branch: String.t() | nil,
          current_branch: String.t() | nil,
          detached?: boolean(),
          upstream_branch: String.t() | nil,
          ahead: non_neg_integer() | nil,
          behind: non_neg_integer() | nil,
          dirty?: boolean(),
          operation: operation(),
          status: [StatusEntriesType.entry()],
          conflicts: [ConflictsType.conflict()]
        }

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(state, _metadata) when is_map(state) do
    if repo_state?(state) do
      {:ok, state}
    else
      :error
    end
  end

  def cast(_raw, _metadata), do: :error

  @keys [
    :path,
    :repo_root,
    :checkout,
    :worktree_name,
    :base_branch,
    :current_branch,
    :detached?,
    :upstream_branch,
    :ahead,
    :behind,
    :dirty?,
    :operation,
    :status,
    :conflicts
  ]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(
        %{
          "status" => status,
          "conflicts" => conflicts,
          "checkout" => checkout,
          "operation" => operation
        } = document
      ) do
    with {:ok, status} <- StatusEntriesType.load(status),
         {:ok, conflicts} <- ConflictsType.load(conflicts),
         {:ok, checkout} <- load_checkout(checkout),
         {:ok, operation} <- load_operation(operation) do
      document
      |> DomovoyCore.Type.atom_keys(@keys)
      |> Map.merge(%{
        status: status,
        conflicts: conflicts,
        checkout: checkout,
        operation: operation
      })
      |> cast()
    end
  end

  def load(_document), do: :error

  @doc """
  Returns every checkout atom this type accepts.
  """
  @spec checkouts() :: [checkout()]
  def checkouts, do: @checkouts

  @doc """
  Returns every operation atom this type accepts.
  """
  @spec operations() :: [operation()]
  def operations, do: @operations

  @spec repo_state?(map()) :: boolean()
  defp repo_state?(state),
    do:
      required_keys?(state) and valid_identity?(state) and valid_tracking?(state) and
        valid_tree?(state)

  @spec required_keys?(map()) :: boolean()
  defp required_keys?(state) do
    match?(
      %{
        path: _,
        repo_root: _,
        checkout: _,
        worktree_name: _,
        base_branch: _,
        current_branch: _,
        detached?: _,
        upstream_branch: _,
        ahead: _,
        behind: _,
        dirty?: _,
        operation: _,
        status: _,
        conflicts: _
      },
      state
    )
  end

  @spec valid_identity?(map()) :: boolean()
  defp valid_identity?(state) do
    valid_path?(state.path) and valid_path?(state.repo_root) and state.checkout in @checkouts and
      optional_string?(state.worktree_name) and optional_string?(state.base_branch) and
      optional_string?(state.current_branch) and is_boolean(state.detached?)
  end

  @spec valid_tracking?(map()) :: boolean()
  defp valid_tracking?(state) do
    optional_string?(state.upstream_branch) and optional_count?(state.ahead) and
      optional_count?(state.behind)
  end

  @spec valid_tree?(map()) :: boolean()
  defp valid_tree?(state) do
    is_boolean(state.dirty?) and state.operation in @operations and is_list(state.status) and
      is_list(state.conflicts)
  end

  @spec valid_path?(any()) :: boolean()
  defp valid_path?(path) when is_binary(path) and path != "", do: true
  defp valid_path?(_other), do: false

  @spec optional_string?(any()) :: boolean()
  defp optional_string?(value) when is_binary(value) and value != "", do: true
  defp optional_string?(nil), do: true
  defp optional_string?(_other), do: false

  @spec optional_count?(any()) :: boolean()
  defp optional_count?(value) when is_integer(value) and value >= 0, do: true
  defp optional_count?(nil), do: true
  defp optional_count?(_other), do: false

  @spec load_checkout(document :: any()) :: {:ok, checkout()} | :error
  defp load_checkout(document) when is_binary(document) do
    case Enum.find(@checkouts, &(Atom.to_string(&1) == document)) do
      nil -> :error
      checkout -> {:ok, checkout}
    end
  end

  defp load_checkout(_document), do: :error

  @spec load_operation(document :: any()) :: {:ok, operation()} | :error
  defp load_operation(document) when is_binary(document) do
    case Enum.find(@operations, &(Atom.to_string(&1) == document)) do
      nil -> :error
      operation -> {:ok, operation}
    end
  end

  defp load_operation(_document), do: :error
end
