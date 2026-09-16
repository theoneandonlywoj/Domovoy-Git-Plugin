defmodule DomovoyGitPlugin.Runner.StatusShort do
  @moduledoc """
  Returns the status of the working tree of a directory. The result has one
  entry for each changed path. Each entry names the state of the index and the
  state of the working tree. It also keeps the raw porcelain code of Git of two
  characters.

  ## Inputs

    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives the list of entries. Usually the type is
  `DomovoyGitPlugin.Type.StatusEntries`. A clean tree gives an empty
  list. An empty list is a correct value and not an error.

  ## Examples

  The runner reads a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGitPlugin.Runner.StatusShort |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "status_short"}
      iex> DomovoyGitPlugin.Runner.StatusShort.run(input, context)
      {:ok,
       [
         %{path: "lib/app.ex", code: " M", index: :unmodified, worktree: :modified},
         %{path: "lib/staged.ex", code: "M ", index: :modified, worktree: :unmodified},
         %{path: "lib/new.ex", code: "??", index: :untracked, worktree: :untracked}
       ]}

  A clean tree gives an empty list:

      iex> DomovoyGitPlugin.Runner.StatusShort.run(input, context)
      {:ok, []}
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
    do: Capabilities.status_short(directory, node_name, :working_directory)
end
