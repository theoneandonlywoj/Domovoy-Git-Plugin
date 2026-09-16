defmodule DomovoyGitPlugin.Runner.WorktreeList do
  @moduledoc """
  Lists every worktree of the repository. Each entry has the branch, the `HEAD`
  and the base branch that Domovoy recorded.

  The first entry of the listing of Git identifies the main checkout. This
  runner does not use `git rev-parse --show-toplevel`. Therefore `main?` is
  correct also when the node runs in a linked worktree.

  ## Inputs

    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives the listing. Usually the type is
  `DomovoyGitPlugin.Type.WorktreeRecords`.

  ## Examples

  The runner reads a repository on the disk, so this example is illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGitPlugin.Runner.WorktreeList |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "worktree_list"}
      iex> DomovoyGitPlugin.Runner.WorktreeList.run(input, context)
      {:ok,
       [
         %{
           worktree_name: nil,
           path: "/repo",
           branch: "main",
           head: "1a2b3c4d5e6f",
           base_branch: nil,
           main?: true
         },
         %{
           worktree_name: "bro-19",
           path: "/repo/.worktrees/bro-19",
           branch: "bro-19-add-metadata",
           head: "7f8e9d0c1b2a",
           base_branch: "main",
           main?: false
         }
       ]}

  A worktree that a person made with `git worktree add` has no record.
  Therefore its `base_branch` is `nil`.
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyGitPlugin.Capabilities
  alias DomovoyGitPlugin.Capabilities.WorktreeMetadata
  alias DomovoyGitPlugin.Type.WorktreeRecords, as: WorktreeRecordsType

  @field :working_directory

  input do
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{working_directory: directory}, %Context{node: node_name}) do
    with {:ok, repository} <- Capabilities.repository(directory, node_name, @field),
         {:ok, records} <- Capabilities.worktree_records(directory, node_name, @field) do
      {:ok, describe_all(records, repository)}
    end
  end

  @spec describe_all([WorktreeMetadata.worktree_record()], WorktreeMetadata.repository()) ::
          [WorktreeRecordsType.worktree()]
  defp describe_all([], _repository), do: []

  defp describe_all(records, repository) do
    main_root = WorktreeMetadata.main_root(records)

    Enum.map(records, fn record -> describe(record, repository, main_root) end)
  end

  @spec describe(
          record :: WorktreeMetadata.worktree_record(),
          repository :: WorktreeMetadata.repository(),
          main_root :: String.t()
        ) :: WorktreeRecordsType.worktree()
  defp describe(record, repository, main_root) do
    main? = record.path == main_root
    worktree_name = if main?, do: nil, else: Path.basename(record.path)

    %{
      worktree_name: worktree_name,
      path: record.path,
      branch: record.branch,
      head: record.head,
      base_branch: base_branch(worktree_name, repository),
      main?: main?
    }
  end

  @spec base_branch(
          worktree_name :: String.t() | nil,
          repository :: WorktreeMetadata.repository()
        ) :: String.t() | nil
  defp base_branch(nil, _repository), do: nil

  defp base_branch(worktree_name, repository),
    do: WorktreeMetadata.read_base_branch(repository.git_common_directory, worktree_name)
end
