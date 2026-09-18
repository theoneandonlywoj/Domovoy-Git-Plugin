defmodule DomovoyGitPlugin.Runner.TrackRemoteBranch do
  @moduledoc """
  Checks out a remote-tracking branch as a local branch and returns a snapshot.

  A missing `refs/remotes/<remote>/<branch>` gives `:remote_branch_not_found`.

  ## Inputs

    * `branch_name` — necessary. A `DomovoyCore.Type.String` with the branch on
      the remote.
    * `remote` — optional. A `DomovoyCore.Type.String`. The default is
      `"origin"`.
    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives `DomovoyGitPlugin.Type.RepoState`.

  ## Examples

  The runner changes a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo", branch_name: "feature"}
      iex> input = DomovoyGitPlugin.Runner.TrackRemoteBranch |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "track"}
      iex> DomovoyGitPlugin.Runner.TrackRemoteBranch.run(input, context)
      {:ok, %{current_branch: "feature", upstream_branch: "origin/feature"}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGitPlugin.Capabilities

  @directory :working_directory
  @branch :branch_name

  input do
    field(:branch_name, StringType)
    field(:remote, StringType, default: "origin")
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:branch_name, :remote, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(
        %Input{branch_name: branch, remote: remote, working_directory: directory},
        %Context{node: node_name}
      ) do
    with :ok <- Capabilities.track_remote_branch(branch, remote, directory, node_name, @branch) do
      Capabilities.repo_state(directory, node_name, @directory)
    end
  end
end
