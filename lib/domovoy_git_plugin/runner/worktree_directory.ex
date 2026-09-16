defmodule DomovoyGitPlugin.Runner.WorktreeDirectory do
  @moduledoc """
  Returns the directory of a managed Git worktree.

  The input is the complete worktree value. The Engine checks the directory with the node output type.

  ## Examples

      iex> input = %DomovoyGitPlugin.Runner.WorktreeDirectory.Input{
      ...>   worktree: %{
      ...>     repo_root: "/repo",
      ...>     name: "bro-52",
      ...>     path: "/repo/.worktrees/bro-52",
      ...>     exists?: true,
      ...>     created?: false,
      ...>     branch: "bro-52-node-inputs"
      ...>   }
      ...> }
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("worktree-directory"), node: "worktree_directory"}
      iex> DomovoyGitPlugin.Runner.WorktreeDirectory.run(input, context)
      {:ok, "/repo/.worktrees/bro-52"}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyGitPlugin.Type.Worktree

  input do
    field(:worktree, Worktree)
  end

  required([:worktree])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{worktree: %{path: path}}, %Context{}), do: {:ok, path}
end
