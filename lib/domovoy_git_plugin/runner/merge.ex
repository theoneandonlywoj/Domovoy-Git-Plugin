defmodule DomovoyGitPlugin.Runner.Merge do
  @moduledoc """
  Merges `ref` into the current branch and returns a snapshot.

  When `fail_on_conflict?` is true, a conflicted stop is `:git_command_failed`.
  When it is false, a conflicted merge returns `RepoState` with
  `operation: :merging`.

  ## Inputs

    * `ref` — necessary. A `DomovoyCore.Type.String` ref to merge.
    * `fail_on_conflict?` — optional `DomovoyCore.Type.Boolean`. The default is
      `true`.
    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives `DomovoyGitPlugin.Type.RepoState`.

  ## Examples

  The runner changes a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo", ref: "feature"}
      iex> input = DomovoyGitPlugin.Runner.Merge |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "merge"}
      iex> DomovoyGitPlugin.Runner.Merge.run(input, context)
      {:ok, %{operation: :idle, conflicts: []}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGitPlugin.Capabilities

  @directory :working_directory
  @ref :ref

  input do
    field(:ref, StringType)
    field(:fail_on_conflict?, BooleanType, default: true)
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:ref, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(
        %Input{ref: ref, fail_on_conflict?: fail_on_conflict?, working_directory: directory},
        %Context{node: node_name}
      ) do
    with :ok <- Capabilities.merge(ref, fail_on_conflict?, directory, node_name, @ref) do
      Capabilities.repo_state(directory, node_name, @directory)
    end
  end
end
