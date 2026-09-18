defmodule DomovoyGitPlugin.Runner.AddAll do
  @moduledoc """
  Stages every change in the working tree and returns a snapshot.

  This runner is separate from `DomovoyGitPlugin.Runner.Add` so a graph cannot
  add the whole tree by accident.

  ## Inputs

    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives `DomovoyGitPlugin.Type.RepoState`.

  ## Examples

  The runner changes a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGitPlugin.Runner.AddAll |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "add_all"}
      iex> DomovoyGitPlugin.Runner.AddAll.run(input, context)
      {:ok, %{dirty?: true}}
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
    with :ok <- Capabilities.add_all(directory, node_name, @directory) do
      Capabilities.repo_state(directory, node_name, @directory)
    end
  end
end
