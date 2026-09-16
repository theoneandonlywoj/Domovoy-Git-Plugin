defmodule DomovoyGitPlugin.Runner.WorktreeResolve do
  @moduledoc """
  Describes the managed worktree with the name `worktree_name`. Makes no
  change to the repository.

  This runner answers whether the worktree is on the disk. A worktree that is
  not there gives `exists?: false`. It does not give an error. Therefore a graph
  makes its decision from the answer and not from an error.

  The runner reads the path of the worktree from the `.worktrees/` of the
  **main** checkout. It takes that location from the worktree list of Git, and
  not from `git rev-parse --show-toplevel`. Therefore the runner gives the same
  answer from the main checkout and from a linked worktree.

  Git does not record the ref that a worktree started from.
  `DomovoyGitPlugin.Runner.WorktreeCreate` writes that ref to a record. This
  runner reads the record and gives the ref as `base_branch`. A worktree that a
  person made by hand has no record. Such a worktree gives `base_branch: nil`.

  ## Inputs

    * `worktree_name` — necessary. A `DomovoyCore.Type.String` with the name.
    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The runner lists `DomovoyGitPlugin.Validator.WorktreeNameIsSafe`. Then a
  node with an unsafe name stops before the runner starts.

  The node `:type` receives the worktree. Usually the type is
  `DomovoyGitPlugin.Type.Worktree`.

  ## Examples

  The runner reads a repository on the disk, so these examples are
  illustrative. A worktree that is on the disk gives its branch and its
  recorded base branch:

      iex> params = %{working_directory: "/repo", worktree_name: "bro-19"}
      iex> input = DomovoyGitPlugin.Runner.WorktreeResolve |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "worktree_resolve"}
      iex> DomovoyGitPlugin.Runner.WorktreeResolve.run(input, context)
      {:ok,
       %{
         repo_root: "/repo",
         name: "bro-19",
         path: "/repo/.worktrees/bro-19",
         exists?: true,
         created?: false,
         branch: "bro-19-add-metadata",
         base_branch: "main"
       }}

  A name that no worktree uses gives `exists?: false`:

      iex> params = %{working_directory: "/repo", worktree_name: "never-made"}
      iex> input = DomovoyGitPlugin.Runner.WorktreeResolve |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> DomovoyGitPlugin.Runner.WorktreeResolve.run(input, context)
      {:ok,
       %{
         repo_root: "/repo",
         name: "never-made",
         path: "/repo/.worktrees/never-made",
         exists?: false,
         created?: false,
         branch: nil,
         base_branch: nil
       }}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGitPlugin.Capabilities
  alias DomovoyGitPlugin.Capabilities.WorktreeMetadata
  alias DomovoyGitPlugin.Error, as: GitError
  alias DomovoyGitPlugin.Validator.WorktreeNameIsSafe

  @field :working_directory

  input do
    field(:worktree_name, StringType)
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:worktree_name, :working_directory])

  validators([WorktreeNameIsSafe])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{worktree_name: worktree_name, working_directory: directory}, %Context{
        node: node_name
      }) do
    with {:ok, repository} <- Capabilities.repository(directory, node_name, @field),
         {:ok, records} <- Capabilities.worktree_records(directory, node_name, @field),
         {:ok, main_root} <- main_root(records, directory, node_name) do
      {:ok, state(main_root, records, repository, worktree_name)}
    end
  end

  @spec main_root(
          records :: [WorktreeMetadata.worktree_record()],
          directory :: String.t(),
          node_name :: DomovoyCore.Node.name()
        ) :: {:ok, String.t()} | Capabilities.failure()
  defp main_root([], directory, node_name),
    do: {:error, GitError.repository_not_resolved(directory, node_name, @field)}

  defp main_root(records, _directory, _node_name), do: {:ok, WorktreeMetadata.main_root(records)}

  @spec state(
          main_root :: String.t(),
          records :: [WorktreeMetadata.worktree_record()],
          repository :: WorktreeMetadata.repository(),
          worktree_name :: String.t()
        ) :: map()
  defp state(main_root, records, repository, worktree_name) do
    path = WorktreeMetadata.worktree_path(main_root, worktree_name)
    record = Enum.find(records, fn record -> record.path == path end)

    %{
      repo_root: main_root,
      name: worktree_name,
      path: path,
      exists?: record != nil,
      created?: false,
      branch: branch(record),
      base_branch: base_branch(record, repository, worktree_name)
    }
  end

  @spec branch(record :: WorktreeMetadata.worktree_record() | nil) :: String.t() | nil
  defp branch(nil), do: nil
  defp branch(record), do: record.branch

  @spec base_branch(
          record :: WorktreeMetadata.worktree_record() | nil,
          repository :: WorktreeMetadata.repository(),
          worktree_name :: String.t()
        ) :: String.t() | nil
  defp base_branch(nil, _repository, _worktree_name), do: nil

  defp base_branch(_record, repository, worktree_name),
    do: WorktreeMetadata.read_base_branch(repository.git_common_directory, worktree_name)
end
