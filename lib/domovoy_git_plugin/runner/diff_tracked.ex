defmodule DomovoyGitPlugin.Runner.DiffTracked do
  @moduledoc """
  Returns the parsed diff of the tracked files between a directory and `HEAD`.

  The diff contains the staged changes and the unstaged changes. It does not
  contain the untracked files. Git cannot make a diff of a file that it does not
  track. Use `DomovoyGitPlugin.Runner.DiffChanges` when you also need the
  untracked files.

  ## Inputs

    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives the parsed diff. Usually the type is
  `DomovoyGitPlugin.Type.Diff`. A clean tree gives an empty list.

  ## Examples

  The runner reads a repository on the disk, so these examples are
  illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGitPlugin.Runner.DiffTracked |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "diff_tracked"}
      iex> DomovoyGitPlugin.Runner.DiffTracked.run(input, context)
      {:ok,
       [
         %{
           file: "lib/app.ex",
           hunks: [
             %{
               header: "@@ -1,3 +1,3 @@",
               old_start_line: 1,
               old_end_line: 3,
               new_start_line: 1,
               new_end_line: 3,
               section: nil,
               added_lines: ["  def new, do: :ok"],
               removed_lines: ["  def old, do: :ok"]
             }
           ]
         }
       ]}

  A clean tree gives an empty list, which is a value and not an error:

      iex> DomovoyGitPlugin.Runner.DiffTracked.run(input, context)
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
    do: Capabilities.diff_tracked(directory, node_name, :working_directory)
end
