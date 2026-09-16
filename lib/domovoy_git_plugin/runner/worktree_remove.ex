defmodule DomovoyGitPlugin.Runner.WorktreeRemove do
  @moduledoc """
  Removes a managed worktree. Can also delete the branch of the worktree.
  Deletes the base-branch record of the worktree.

  You must select both destructive options. They are not the default. Without
  `force?`, Git refuses to remove a worktree that holds uncommitted changes. This
  runner passes that refusal on as an error. It does not prevent the refusal.
  Thus the caller sees the explanation of Git.

  ## Inputs

    * `worktree_name` — necessary. A `DomovoyCore.Type.String` with the name.
    * `force?` — optional `DomovoyCore.Type.Boolean`. The default is `false`. It
      removes the worktree also when the worktree holds uncommitted changes.
    * `delete_branch?` — optional `DomovoyCore.Type.Boolean`. The default is
      `false`. It deletes the branch of the worktree after the removal.
    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The runner lists `DomovoyGitPlugin.Validator.WorktreeNameIsSafe`. Then a
  node with an unsafe name stops before the runner starts.

  The node `:type` receives the result of the removal. Usually the type is
  `DomovoyGitPlugin.Type.WorktreeRemovalStatus`.

  ## Examples

  The runner changes a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo", delete_branch?: true, worktree_name: "bro-19"}
      iex> input = DomovoyGitPlugin.Runner.WorktreeRemove |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "worktree_remove"}
      iex> DomovoyGitPlugin.Runner.WorktreeRemove.run(input, context)
      {:ok,
       %{
         worktree_name: "bro-19",
         path: "/repo/.worktrees/bro-19",
         branch: "bro-19-add-metadata",
         removed?: true,
         branch_deleted?: true
       }}

  A worktree with uncommitted changes, and `force?` not set, gives the error of
  Git:

      iex> DomovoyGitPlugin.Runner.WorktreeRemove.run(input, context)
      {:error,
       %DomovoyCore.Error{
         type: :git_command_failed,
         reason: "command exited with status 128: fatal: contains modified or untracked files",
         metadata: %{
           command: ["git", "worktree", "remove", "/repo/.worktrees/bro-19"],
           node_name: "worktree_remove",
           field_name: :worktree_name
         }
       }}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGitPlugin.Capabilities
  alias DomovoyGitPlugin.Capabilities.WorktreeMetadata
  alias DomovoyGitPlugin.Validator.WorktreeNameIsSafe

  @directory :working_directory
  @name :worktree_name

  input do
    field(:worktree_name, StringType)
    field(:force?, BooleanType, default: false)
    field(:delete_branch?, BooleanType, default: false)
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:worktree_name, :working_directory])

  validators([WorktreeNameIsSafe])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    %Input{
      worktree_name: worktree_name,
      force?: force?,
      delete_branch?: delete_branch?,
      working_directory: directory
    } = input

    with {:ok, repository} <- Capabilities.repository(directory, node_name, @directory),
         {:ok, worktree} <-
           Capabilities.worktree_resolve(worktree_name, directory, node_name, @name),
         {:ok, _output} <-
           Capabilities.worktree_remove(worktree.path, force?, directory, node_name, @name),
         {:ok, branch_deleted?} <- delete_branch(worktree, delete_branch?, directory, node_name) do
      WorktreeMetadata.delete_record(repository.git_common_directory, worktree_name)

      {:ok,
       %{
         worktree_name: worktree_name,
         path: worktree.path,
         branch: worktree.branch,
         removed?: true,
         branch_deleted?: branch_deleted?
       }}
    end
  end

  @spec delete_branch(
          worktree :: map(),
          delete_branch? :: boolean(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, boolean()} | Capabilities.failure()
  defp delete_branch(%{branch: branch}, true, directory, node_name) when is_binary(branch) do
    with {:ok, _output} <- Capabilities.delete_branch(branch, directory, node_name, @name) do
      {:ok, true}
    end
  end

  defp delete_branch(_worktree, _delete_branch?, _directory, _node_name), do: {:ok, false}
end
