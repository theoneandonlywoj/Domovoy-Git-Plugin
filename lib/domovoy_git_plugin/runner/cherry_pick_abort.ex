defmodule DomovoyGitPlugin.Runner.CherryPickAbort do
  @moduledoc """
  Aborts an in-progress cherry-pick and returns a snapshot with
  `operation: :idle`.

  ## Inputs

    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives `DomovoyGitPlugin.Type.RepoState`.

  ## Examples

  The runner changes a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGitPlugin.Runner.CherryPickAbort |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "cherry_pick_abort"}
      iex> DomovoyGitPlugin.Runner.CherryPickAbort.run(input, context)
      {:ok, %{operation: :idle, conflicts: []}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyGitPlugin.Capabilities

  @directory :working_directory

  input do
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{working_directory: directory}, %Context{node: node_name}) do
    with :ok <- Capabilities.cherry_pick_abort(directory, node_name, @directory) do
      Capabilities.repo_state(directory, node_name, @directory)
    end
  end
end
