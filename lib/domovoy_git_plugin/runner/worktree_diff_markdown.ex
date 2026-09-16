defmodule DomovoyGitPlugin.Runner.WorktreeDiffMarkdown do
  @moduledoc """
  Returns everything that a worktree changed against its base branch, as a
  Markdown document for a person.

  The runner collects the same changes as `DomovoyGitPlugin.Runner.WorktreeDiff`.
  Then `DomovoyGitPlugin.Capabilities.DiffMarkdown` renders them.

  ## Inputs

    * `worktree` — necessary, as in `DomovoyGitPlugin.Runner.WorktreeDiff`.
    * `base_branch` — optional, as in `DomovoyGitPlugin.Runner.WorktreeDiff`.

  The node `:type` receives the document. The type is `DomovoyCore.Type.String`.

  ## Examples

  The runner reads a repository on the disk, so this example is illustrative.

      iex> worktree = %{
      ...>   repo_root: "/repo",
      ...>   name: "bro-19",
      ...>   path: "/repo/.worktrees/bro-19",
      ...>   exists?: true,
      ...>   created?: false,
      ...>   branch: "bro-19-add-metadata",
      ...>   base_branch: "main"
      ...> }
      iex> input = DomovoyGitPlugin.Runner.WorktreeDiffMarkdown |> DomovoyCore.Runner.changeset(%{worktree: worktree}) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "worktree_diff"}
      iex> DomovoyGitPlugin.Runner.WorktreeDiffMarkdown.run(input, context)
      {:ok,
       "# Worktree bro-19\\n\\n- Branch: `bro-19-add-metadata`\\n" <>
         "- Base branch: `main`\\n- Path: `/repo/.worktrees/bro-19`\\n\\n" <>
         "## lib/app.ex\\n\\n```diff\\n@@ -10,3 +10,3 @@ defmodule App do\\n" <>
         "-  def old, do: :ok\\n+  def new, do: :ok\\n```\\n"}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGitPlugin.Capabilities
  alias DomovoyGitPlugin.Capabilities.DiffMarkdown
  alias DomovoyGitPlugin.Type.Worktree, as: WorktreeType

  input do
    field(:worktree, WorktreeType)
    field(:base_branch, StringType)
  end

  required([:worktree])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{worktree: worktree, base_branch: base_branch}, %Context{node: node_name}) do
    with {:ok, %{files: files} = diff} <-
           Capabilities.worktree_changes(worktree, base_branch, node_name) do
      {:ok, DiffMarkdown.render(files, Map.delete(diff, :files))}
    end
  end
end
