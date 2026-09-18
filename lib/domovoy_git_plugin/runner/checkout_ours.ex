defmodule DomovoyGitPlugin.Runner.CheckoutOurs do
  @moduledoc """
  Checks out the `--ours` stage of the given paths and returns a snapshot.

  This runner does not `git add`. The graph still stages the paths afterwards.

  ## Inputs

    * `paths` — necessary. A `DomovoyGitPlugin.Type.Paths` list.
    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives `DomovoyGitPlugin.Type.RepoState`.

  ## Examples

  The runner changes a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo", paths: ["README.md"]}
      iex> input = DomovoyGitPlugin.Runner.CheckoutOurs |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "checkout_ours"}
      iex> DomovoyGitPlugin.Runner.CheckoutOurs.run(input, context)
      {:ok, %{operation: :merging}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyGitPlugin.Capabilities
  alias DomovoyGitPlugin.Type.Paths, as: PathsType
  alias DomovoyGitPlugin.Validator.PathsPresent

  @directory :working_directory
  @paths :paths

  input do
    field(:paths, PathsType)
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:paths, :working_directory])

  validators([PathsPresent])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{paths: paths, working_directory: directory}, %Context{node: node_name}) do
    with :ok <- Capabilities.checkout_ours(paths, directory, node_name, @paths) do
      Capabilities.repo_state(directory, node_name, @directory)
    end
  end
end
