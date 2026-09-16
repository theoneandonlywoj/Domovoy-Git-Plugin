defmodule DomovoyGitPlugin.Runner.CurrentBranch do
  @moduledoc """
  Returns the branch that is checked out in a directory.

  ## Inputs

    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory. Bind it to a node that gives a directory, such
      as `DomovoyGitPlugin.Runner.WorktreeDirectory`.

  The node `:type` receives the branch name. Usually the type is
  `DomovoyCore.Type.String`. If the HEAD is detached, this runner returns the
  text `"HEAD"`. It does not return an error. If you want an error for a
  detached HEAD, use `DomovoyGitPlugin.Capabilities.current_branch/3`.

  ## Examples

  The runner reads a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGitPlugin.Runner.CurrentBranch |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "current_branch"}
      iex> DomovoyGitPlugin.Runner.CurrentBranch.run(input, context)
      {:ok, "bro-19-add-metadata"}

  A detached checkout gives the text `"HEAD"` and not an error:

      iex> DomovoyGitPlugin.Runner.CurrentBranch.run(input, context)
      {:ok, "HEAD"}

  A directory that is not a repository gives an error:

      iex> DomovoyGitPlugin.Runner.CurrentBranch.run(input, context)
      {:error,
       %DomovoyCore.Error{
         type: :git_command_failed,
         reason: "command exited with status 128: fatal: not a git repository",
         metadata: %{
           command: ["git", "rev-parse", "--abbrev-ref", "HEAD"],
           node_name: "current_branch",
           field_name: :working_directory
         }
       }}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyGitPlugin.Capabilities

  input do
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{working_directory: directory}, %Context{node: node_name}),
    do: Capabilities.current_branch_abbrev(directory, node_name, :working_directory)
end
