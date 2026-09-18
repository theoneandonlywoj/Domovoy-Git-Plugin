defmodule DomovoyGitPlugin.Runner.Checkout do
  @moduledoc """
  Checks out a local branch and returns a snapshot of the checkout.

  The branch must already exist as `refs/heads/<branch>`. A missing name gives
  `:branch_not_found` and does not create the branch. A dirty working tree
  fails as Git fails. There is no `--force`.

  ## Inputs

    * `branch_name` — necessary. A `DomovoyCore.Type.String` with the local
      branch to check out.
    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives `DomovoyGitPlugin.Type.RepoState`.

  ## Examples

  The runner changes a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo", branch_name: "feature"}
      iex> input = DomovoyGitPlugin.Runner.Checkout |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "checkout"}
      iex> DomovoyGitPlugin.Runner.Checkout.run(input, context)
      {:ok, %{current_branch: "feature", checkout: :main, operation: :idle, conflicts: []}}
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
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:branch_name, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{branch_name: branch, working_directory: directory}, %Context{node: node_name}) do
    with :ok <- Capabilities.checkout(branch, directory, node_name, @branch) do
      Capabilities.repo_state(directory, node_name, @directory)
    end
  end
end
