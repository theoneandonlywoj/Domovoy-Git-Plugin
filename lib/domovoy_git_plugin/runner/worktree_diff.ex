defmodule DomovoyGitPlugin.Runner.WorktreeDiff do
  @moduledoc """
  Returns everything that a worktree changed against its base branch, as
  structured data.

  One `git diff <base>` against the worktree gives its commits, its staged
  changes and its unstaged changes together. The runner collects the untracked
  files separately and adds them at the end.

  ## Inputs

    * `worktree` — necessary. The complete `DomovoyGitPlugin.Type.Worktree`
      value. Bind it to a node that gives a worktree, such as
      `DomovoyGitPlugin.Runner.WorktreeResolve`.
    * `base_branch` — optional. A `DomovoyCore.Type.String` ref. If the node does
      not supply it, the runner uses the `base_branch` of the worktree. A
      worktree that a person made by hand has no record. For such a worktree
      you must give a base branch.

  The node `:type` receives the map that `DomovoyGitPlugin.Type.WorktreeDiff`
  describes. A node that wants the same information as Markdown uses
  `DomovoyGitPlugin.Runner.WorktreeDiffMarkdown`.

  ## Examples

  The runner reads a repository on the disk, so these examples are
  illustrative.

      iex> worktree = %{
      ...>   repo_root: "/repo",
      ...>   name: "bro-19",
      ...>   path: "/repo/.worktrees/bro-19",
      ...>   exists?: true,
      ...>   created?: false,
      ...>   branch: "bro-19-add-metadata",
      ...>   base_branch: "main"
      ...> }
      iex> input = DomovoyGitPlugin.Runner.WorktreeDiff |> DomovoyCore.Runner.changeset(%{worktree: worktree}) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "worktree_diff"}
      iex> DomovoyGitPlugin.Runner.WorktreeDiff.run(input, context)
      {:ok,
       %{
         worktree_name: "bro-19",
         path: "/repo/.worktrees/bro-19",
         branch: "bro-19-add-metadata",
         base_branch: "main",
         files: [
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
         ]
       }}

  A worktree without a recorded base branch, and no `base_branch` argument,
  gives an error:

      iex> worktree = %{worktree | base_branch: nil}
      iex> input = DomovoyGitPlugin.Runner.WorktreeDiff |> DomovoyCore.Runner.changeset(%{worktree: worktree}) |> Ecto.Changeset.apply_changes()
      iex> DomovoyGitPlugin.Runner.WorktreeDiff.run(input, context)
      {:error,
       %DomovoyCore.Error{
         type: :git_worktree_diff_failed,
         reason: ~s(worktree "bro-19" has no recorded base branch; supply base_branch),
         metadata: %{node_name: "worktree_diff", field_name: :base_branch}
       }}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGitPlugin.Capabilities
  alias DomovoyGitPlugin.Type.Worktree, as: WorktreeType

  input do
    field(:worktree, WorktreeType)
    field(:base_branch, StringType)
  end

  required([:worktree])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{worktree: worktree, base_branch: base_branch}, %Context{node: node_name}),
    do: Capabilities.worktree_changes(worktree, base_branch, node_name)
end
