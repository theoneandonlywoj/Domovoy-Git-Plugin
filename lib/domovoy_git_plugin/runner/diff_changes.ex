defmodule DomovoyGitPlugin.Runner.DiffChanges do
  @moduledoc """
  Returns the parsed diff of every change in the working tree. This includes the
  staged changes, the unstaged changes and the untracked files.

  The runner joins the tracked diff against `HEAD` with one diff for each
  untracked file. Therefore it reports everything in the working tree. The
  tracked entries come first, in the order that Git lists them.

  ## Inputs

    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The node `:type` receives the parsed diff. Usually the type is
  `DomovoyGitPlugin.Type.Diff`.

  ## Examples

  The runner reads a repository on the disk, so this example is illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGitPlugin.Runner.DiffChanges |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "diff_changes"}
      iex> DomovoyGitPlugin.Runner.DiffChanges.run(input, context)
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
         },
         %{
           file: "lib/untracked.ex",
           hunks: [
             %{
               header: "@@ -0,0 +1,3 @@",
               old_start_line: nil,
               old_end_line: nil,
               new_start_line: 1,
               new_end_line: 3,
               section: nil,
               added_lines: ["defmodule Untracked do", "  @moduledoc false", "end"],
               removed_lines: []
             }
           ]
         }
       ]}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyGitPlugin.Capabilities

  @field :working_directory

  input do
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{working_directory: directory}, %Context{node: node_name}) do
    with {:ok, tracked} <- Capabilities.diff_tracked(directory, node_name, @field),
         {:ok, untracked} <- Capabilities.untracked_diff(directory, node_name, @field) do
      {:ok, tracked ++ untracked}
    end
  end
end
