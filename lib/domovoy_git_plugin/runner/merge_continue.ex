defmodule DomovoyGitPlugin.Runner.MergeContinue do
  @moduledoc """
  Continues an in-progress merge and returns a snapshot.

  Git uses the existing `MERGE_MSG`. Remaining conflicts fail, unless
  `fail_on_conflict?` is false and the checkout is still merging.

  ## Inputs

    * `fail_on_conflict?` — optional `DomovoyCore.Type.Boolean`. The default is
      `true`.
    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives `DomovoyGitPlugin.Type.RepoState`.

  ## Examples

  The runner changes a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGitPlugin.Runner.MergeContinue |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "merge_continue"}
      iex> DomovoyGitPlugin.Runner.MergeContinue.run(input, context)
      {:ok, %{operation: :idle, conflicts: []}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyGitPlugin.Capabilities

  @directory :working_directory

  input do
    field(:fail_on_conflict?, BooleanType, default: true)
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(
        %Input{fail_on_conflict?: fail_on_conflict?, working_directory: directory},
        %Context{node: node_name}
      ) do
    with :ok <- Capabilities.merge_continue(fail_on_conflict?, directory, node_name, @directory) do
      Capabilities.repo_state(directory, node_name, @directory)
    end
  end
end
