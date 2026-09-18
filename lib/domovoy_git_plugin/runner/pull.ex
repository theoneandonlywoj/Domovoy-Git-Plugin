defmodule DomovoyGitPlugin.Runner.Pull do
  @moduledoc """
  Fetches a remote and merges or rebases the fetched ref, then returns a
  snapshot.

  This is fetch plus merge or rebase, not `git pull`, so conflict policy is one
  code path. The fetch timeout is 120 seconds.

  ## Inputs

    * `remote` — optional. A `DomovoyCore.Type.String`. The default is
      `"origin"`.
    * `refspec` — optional. A `DomovoyCore.Type.String` refspec to fetch.
    * `rebase?` — optional `DomovoyCore.Type.Boolean`. The default is `false`.
    * `fail_on_conflict?` — optional `DomovoyCore.Type.Boolean`. The default is
      `true`.
    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives `DomovoyGitPlugin.Type.RepoState`.

  ## Examples

  The runner changes a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGitPlugin.Runner.Pull |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "pull"}
      iex> DomovoyGitPlugin.Runner.Pull.run(input, context)
      {:ok, %{current_branch: "main", behind: 0}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGitPlugin.Capabilities

  @directory :working_directory

  input do
    field(:remote, StringType, default: "origin")
    field(:refspec, StringType)
    field(:rebase?, BooleanType, default: false)
    field(:fail_on_conflict?, BooleanType, default: true)
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:remote, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    %Input{
      remote: remote,
      refspec: refspec,
      rebase?: rebase?,
      fail_on_conflict?: fail_on_conflict?,
      working_directory: directory
    } = input

    with :ok <-
           Capabilities.pull(
             remote,
             refspec,
             rebase?,
             fail_on_conflict?,
             directory,
             node_name,
             @directory
           ) do
      Capabilities.repo_state(directory, node_name, @directory)
    end
  end
end
