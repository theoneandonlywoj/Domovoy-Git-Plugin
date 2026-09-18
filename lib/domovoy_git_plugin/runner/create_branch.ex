defmodule DomovoyGitPlugin.Runner.CreateBranch do
  @moduledoc """
  Creates a branch, checks it out, and returns a snapshot of the checkout.

  `start_point` is optional. When the node does not supply it, Git uses `HEAD`.
  An existing branch name fails as Git fails.

  ## Inputs

    * `branch_name` — necessary. A `DomovoyCore.Type.String` with the branch to
      create.
    * `start_point` — optional. A `DomovoyCore.Type.String` ref.
    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives `DomovoyGitPlugin.Type.RepoState`.

  ## Examples

  The runner changes a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo", branch_name: "feature"}
      iex> input = DomovoyGitPlugin.Runner.CreateBranch |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "create_branch"}
      iex> DomovoyGitPlugin.Runner.CreateBranch.run(input, context)
      {:ok, %{current_branch: "feature", upstream_branch: nil}}
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
    field(:start_point, StringType)
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:branch_name, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(
        %Input{branch_name: branch, start_point: start_point, working_directory: directory},
        %Context{node: node_name}
      ) do
    with :ok <- Capabilities.create_branch(branch, start_point, directory, node_name, @branch) do
      Capabilities.repo_state(directory, node_name, @directory)
    end
  end
end
