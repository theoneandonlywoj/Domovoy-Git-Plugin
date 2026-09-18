defmodule DomovoyGitPlugin.Runner.Fetch do
  @moduledoc """
  Fetches a remote and returns a snapshot of the checkout.

  The timeout is 120 seconds. There is no prune and no tags flag.

  ## Inputs

    * `remote` — optional. A `DomovoyCore.Type.String`. The default is
      `"origin"`.
    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives `DomovoyGitPlugin.Type.RepoState`.

  ## Examples

  The runner reads a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGitPlugin.Runner.Fetch |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "fetch"}
      iex> DomovoyGitPlugin.Runner.Fetch.run(input, context)
      {:ok, %{current_branch: "main", upstream_branch: "origin/main", behind: 0}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGitPlugin.Capabilities

  @directory :working_directory

  input do
    field(:remote, StringType, default: "origin")
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:remote, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{remote: remote, working_directory: directory}, %Context{node: node_name}) do
    with {:ok, _output} <- Capabilities.fetch(remote, directory, node_name, @directory) do
      Capabilities.repo_state(directory, node_name, @directory)
    end
  end
end
