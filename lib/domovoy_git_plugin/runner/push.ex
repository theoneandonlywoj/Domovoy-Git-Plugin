defmodule DomovoyGitPlugin.Runner.Push do
  @moduledoc """
  Pushes to a remote and returns a snapshot of the checkout.

  There is no `--force` and no `--force-with-lease`. A branch with no upstream
  and `set_upstream?: false` fails as Git fails. The timeout is 120 seconds.

  ## Inputs

    * `remote` — optional. A `DomovoyCore.Type.String`. The default is
      `"origin"`.
    * `refspec` — optional. A `DomovoyCore.Type.String`. When missing, Git uses
      the configured upstream.
    * `set_upstream?` — optional `DomovoyCore.Type.Boolean`. The default is
      `false`.
    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives `DomovoyGitPlugin.Type.RepoState`.

  ## Examples

  The runner changes a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo", set_upstream?: true}
      iex> input = DomovoyGitPlugin.Runner.Push |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "push"}
      iex> DomovoyGitPlugin.Runner.Push.run(input, context)
      {:ok, %{current_branch: "main", ahead: 0}}
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
    field(:set_upstream?, BooleanType, default: false)
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:remote, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(
        %Input{
          remote: remote,
          refspec: refspec,
          set_upstream?: set_upstream?,
          working_directory: directory
        },
        %Context{node: node_name}
      ) do
    with :ok <-
           Capabilities.push(remote, refspec, set_upstream?, directory, node_name, @directory) do
      Capabilities.repo_state(directory, node_name, @directory)
    end
  end
end
