defmodule DomovoyGitPlugin.Runner.Commit do
  @moduledoc """
  Creates a commit and returns a snapshot of the checkout.

  Identity is the repository `user.name` and `user.email`. A missing identity
  fails as Git fails. There is no `--amend`, no `--no-verify`, and no signing
  flag. An empty message after trim does not start the node.

  ## Inputs

    * `message` — necessary. A `DomovoyCore.Type.String` commit message.
    * `allow_empty?` — optional `DomovoyCore.Type.Boolean`. The default is
      `false`.
    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives `DomovoyGitPlugin.Type.RepoState`. A successful
  commit on a previously merging repo shows `operation: :idle` and
  `conflicts: []`.

  ## Examples

  The runner changes a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo", message: "Add the snapshot"}
      iex> input = DomovoyGitPlugin.Runner.Commit |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "commit"}
      iex> DomovoyGitPlugin.Runner.Commit.run(input, context)
      {:ok, %{operation: :idle, conflicts: [], dirty?: false}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGitPlugin.Capabilities
  alias DomovoyGitPlugin.Validator.CommitMessagePresent

  @directory :working_directory
  @message :message

  input do
    field(:message, StringType)
    field(:allow_empty?, BooleanType, default: false)
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:message, :working_directory])

  validators([CommitMessagePresent])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(
        %Input{message: message, allow_empty?: allow_empty?, working_directory: directory},
        %Context{node: node_name}
      ) do
    with :ok <- Capabilities.commit(message, allow_empty?, directory, node_name, @message) do
      Capabilities.repo_state(directory, node_name, @directory)
    end
  end
end
