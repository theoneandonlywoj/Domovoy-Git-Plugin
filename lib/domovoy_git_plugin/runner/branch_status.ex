defmodule DomovoyGitPlugin.Runner.BranchStatus do
  @moduledoc """
  Returns the branch that is checked out, its upstream branch, and the status of
  the working tree, as one value.

  The pre-commit step, the pre-push step and the pull-request step all need this
  information. Therefore they ask Git one time and not three times. A branch
  without an upstream gives `upstream_branch: nil`. It does not give an error. A
  new branch normally has no upstream.

  ## Inputs

    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives the composed map. Usually the type is
  `DomovoyGitPlugin.Type.BranchStatus`.

  ## Examples

  The runner reads a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGitPlugin.Runner.BranchStatus |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "branch_status"}
      iex> DomovoyGitPlugin.Runner.BranchStatus.run(input, context)
      {:ok,
       %{
         current_branch: "bro-19-add-metadata",
         upstream_branch: "origin/bro-19-add-metadata",
         status: [
           %{path: "lib/app.ex", code: " M", index: :unmodified, worktree: :modified},
           %{path: "lib/new.ex", code: "??", index: :untracked, worktree: :untracked}
         ]
       }}

  A new branch without an upstream, in a clean tree:

      iex> DomovoyGitPlugin.Runner.BranchStatus.run(input, context)
      {:ok, %{current_branch: "bro-20-new-work", upstream_branch: nil, status: []}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyGitPlugin.Capabilities

  @field :working_directory

  input do
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{working_directory: directory}, %Context{node: node_name}) do
    with {:ok, current_branch} <- Capabilities.current_branch_abbrev(directory, node_name, @field),
         {:ok, status} <- Capabilities.status_short(directory, node_name, @field),
         {:ok, upstream_branch} <- Capabilities.upstream_branch(directory) do
      {:ok, %{current_branch: current_branch, upstream_branch: upstream_branch, status: status}}
    end
  end
end
