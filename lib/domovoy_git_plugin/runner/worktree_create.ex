defmodule DomovoyGitPlugin.Runner.WorktreeCreate do
  @moduledoc """
  Creates a managed worktree in the `.worktrees/` of the main checkout, on a new
  branch that starts from a base ref. Records that base branch.

  Git does not store the ref that a worktree started from. Therefore this runner
  writes the ref to `<git-common-dir>/domovoy/worktrees/<worktree_name>.json`.
  `DomovoyGitPlugin.Runner.WorktreeResolve` reads that record later, and
  `DomovoyGitPlugin.Runner.WorktreeDiff` then compares the worktree with its
  start point without more information.

  The runner puts the worktree in the `.worktrees/` of the **main** checkout. It
  takes the location from the worktree list of Git, and not from
  `git rev-parse --show-toplevel`. Therefore this runner cannot put one worktree
  in another worktree when it runs in a linked worktree.

  Creation is only the first step. `DomovoyWorkflows.Runner.CopyWorktreeArtifact` copies
  the local build artifacts of the repository into the new worktree.
  `PluginDomovoyMise.Runner.Trust` trusts the toolchain configuration of the
  worktree. Both of them use the `DomovoyGitPlugin.Type.Worktree` that this runner
  makes. Therefore a graph joins them as separate nodes. It does not hide them
  in this runner.

  ## Inputs

    * `worktree_name` — necessary. A `DomovoyCore.Type.String` with the name.
    * `branch_name` — necessary. A `DomovoyCore.Type.String` with the branch to
      make.
    * `base_branch` — necessary. A `DomovoyCore.Type.String` with the ref that the
      branch starts from.
    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The runner lists `DomovoyGitPlugin.Validator.WorktreeNameIsSafe`. Then a
  node with an unsafe name stops before the runner starts.

  The node `:type` receives the new worktree. Usually the type is
  `DomovoyGitPlugin.Type.Worktree`.

  ## Examples

  The runner changes a repository on the disk, so these examples are
  illustrative.

      iex> params = %{
      ...>   working_directory: "/repo",
      ...>   worktree_name: "bro-19",
      ...>   branch_name: "bro-19-add-metadata",
      ...>   base_branch: "main"
      ...> }
      iex> input = DomovoyGitPlugin.Runner.WorktreeCreate |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "worktree_create"}
      iex> DomovoyGitPlugin.Runner.WorktreeCreate.run(input, context)
      {:ok,
       %{
         repo_root: "/repo",
         name: "bro-19",
         path: "/repo/.worktrees/bro-19",
         exists?: true,
         created?: true,
         branch: "bro-19-add-metadata",
         base_branch: "main"
       }}

  The runner also writes `/repo/.git/domovoy/worktrees/bro-19.json`:

      {"worktree_name":"bro-19","path":"/repo/.worktrees/bro-19",
       "branch":"bro-19-add-metadata","base_branch":"main"}

  A second run for the same name gives an error, because the path is taken:

      iex> DomovoyGitPlugin.Runner.WorktreeCreate.run(input, context)
      {:error,
       %DomovoyCore.Error{
         type: :worktree_already_exists,
         metadata: %{
           worktree_name: "bro-19",
           path: "/repo/.worktrees/bro-19",
           node_name: "worktree_create",
           field_name: :worktree_name
         }
       }}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGitPlugin.Capabilities
  alias DomovoyGitPlugin.Capabilities.WorktreeMetadata
  alias DomovoyGitPlugin.Error, as: GitError
  alias DomovoyGitPlugin.Validator.WorktreeNameIsSafe

  @directory :working_directory
  @name :worktree_name

  input do
    field(:worktree_name, StringType)
    field(:branch_name, StringType)
    field(:base_branch, StringType)
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:worktree_name, :branch_name, :base_branch, :working_directory])

  validators([WorktreeNameIsSafe])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    %Input{
      worktree_name: worktree_name,
      branch_name: branch_name,
      base_branch: base_branch,
      working_directory: directory
    } = input

    with {:ok, repository} <- Capabilities.repository(directory, node_name, @directory),
         {:ok, records} <- Capabilities.worktree_records(directory, node_name, @directory),
         {:ok, path} <- worktree_path(records, worktree_name, directory, node_name),
         {:ok, _output} <-
           Capabilities.worktree_add(
             path,
             branch_name,
             base_branch,
             directory,
             node_name,
             @directory
           ),
         :ok <- write_record(repository, worktree_name, path, branch_name, base_branch, node_name) do
      {:ok,
       %{
         repo_root: WorktreeMetadata.main_root(records),
         name: worktree_name,
         path: path,
         exists?: true,
         created?: true,
         branch: branch_name,
         base_branch: base_branch
       }}
    end
  end

  @spec worktree_path(
          records :: [WorktreeMetadata.worktree_record()],
          worktree_name :: String.t(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, String.t()} | Capabilities.failure()
  defp worktree_path([], _worktree_name, directory, node_name),
    do: {:error, GitError.repository_not_resolved(directory, node_name, @directory)}

  defp worktree_path(records, worktree_name, _directory, node_name) do
    path =
      records
      |> WorktreeMetadata.main_root()
      |> WorktreeMetadata.worktree_path(worktree_name)

    if File.exists?(path) do
      {:error, GitError.worktree_already_exists(worktree_name, path, node_name, @name)}
    else
      {:ok, path}
    end
  end

  @spec write_record(
          repository :: WorktreeMetadata.repository(),
          worktree_name :: String.t(),
          path :: String.t(),
          branch_name :: String.t(),
          base_branch :: String.t(),
          node_name :: Node.name()
        ) :: :ok | Capabilities.failure()
  defp write_record(repository, worktree_name, path, branch_name, base_branch, node_name) do
    attributes = %{path: path, branch: branch_name, base_branch: base_branch}

    case WorktreeMetadata.write_record(repository.git_common_directory, worktree_name, attributes) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, GitError.write_worktree_record_failed(reason, worktree_name, node_name, @name)}
    end
  end
end
