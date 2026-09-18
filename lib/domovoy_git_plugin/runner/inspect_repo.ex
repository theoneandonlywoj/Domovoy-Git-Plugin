defmodule DomovoyGitPlugin.Runner.InspectRepo do
  @moduledoc """
  Returns a snapshot of one Git checkout.

  The snapshot is `DomovoyGitPlugin.Type.RepoState`. It describes **this**
  checkout from `working_directory`. That directory may be the main worktree or
  a linked worktree.

  ## Inputs

    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives the snapshot. Usually the type is
  `DomovoyGitPlugin.Type.RepoState`.

  ## Examples

  The runner reads a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGitPlugin.Runner.InspectRepo |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "inspect_repo"}
      iex> DomovoyGitPlugin.Runner.InspectRepo.run(input, context)
      {:ok,
       %{
         path: "/repo",
         repo_root: "/repo",
         checkout: :main,
         worktree_name: nil,
         base_branch: nil,
         current_branch: "main",
         detached?: false,
         upstream_branch: "origin/main",
         ahead: 0,
         behind: 0,
         dirty?: false,
         operation: :idle,
         status: [],
         conflicts: []
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
    do: Capabilities.repo_state(directory, node_name, :working_directory)
end
