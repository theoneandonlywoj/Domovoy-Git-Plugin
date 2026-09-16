defmodule DomovoyGitPlugin.Runner.BranchDiff do
  @moduledoc """
  Returns the parsed diff between two refs.

  The runner compares the refs with `base..target`. Therefore the result shows
  what `target` has and `base` does not have, measured from their merge base.

  ## Inputs

    * `base_branch` — necessary. A `DomovoyCore.Type.String` ref.
    * `target_branch` — necessary. A `DomovoyCore.Type.String` ref.
    * `working_directory` — optional, as in
      `DomovoyGitPlugin.Runner.CurrentBranch`.

  The runner lists `DomovoyGitPlugin.Validator.DiffRefsPresent`. Then a node
  with a blank ref stops before the runner starts.

  The node `:type` receives the parsed diff. Usually the type is
  `DomovoyGitPlugin.Type.Diff`.

  ## Examples

  The runner reads a repository on the disk, so these examples are
  illustrative.

      iex> params = %{
      ...>   working_directory: "/repo",
      ...>   base_branch: "main",
      ...>   target_branch: "bro-19-add-metadata"
      ...> }
      iex> input = DomovoyGitPlugin.Runner.BranchDiff |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "branch_diff"}
      iex> DomovoyGitPlugin.Runner.BranchDiff.run(input, context)
      {:ok,
       [
         %{
           file: "lib/app.ex",
           hunks: [
             %{
               header: "@@ -10,3 +10,3 @@ defmodule App do",
               old_start_line: 10,
               old_end_line: 12,
               new_start_line: 10,
               new_end_line: 12,
               section: "defmodule App do",
               added_lines: ["  def new, do: :ok"],
               removed_lines: ["  def old, do: :ok"]
             }
           ]
         }
       ]}

  Two refs that are the same give an empty diff:

      iex> DomovoyGitPlugin.Runner.BranchDiff.run(input, context)
      {:ok, []}

  A ref that Git does not know gives an error:

      iex> DomovoyGitPlugin.Runner.BranchDiff.run(input, context)
      {:error,
       %DomovoyCore.Error{
         type: :git_command_failed,
         reason: "command exited with status 128: fatal: bad revision",
         metadata: %{
           command: ["git", "diff", "main..no-such-branch"],
           node_name: "branch_diff",
           field_name: :working_directory
         }
       }}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGitPlugin.Capabilities
  alias DomovoyGitPlugin.Validator.DiffRefsPresent

  input do
    field(:base_branch, StringType)
    field(:target_branch, StringType)
    field(:working_directory, DomovoyCore.Type.Directory, default: ".")
  end

  required([:base_branch, :target_branch, :working_directory])

  validators([DiffRefsPresent])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    %Input{base_branch: base, target_branch: target, working_directory: directory} = input

    Capabilities.branch_diff(base, target, directory, node_name, :working_directory)
  end
end
