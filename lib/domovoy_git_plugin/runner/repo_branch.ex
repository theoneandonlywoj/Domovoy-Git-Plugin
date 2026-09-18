defmodule DomovoyGitPlugin.Runner.RepoBranch do
  @moduledoc """
  Returns the current branch from a `RepoState`.

  If the checkout is detached, this runner gives the text `"HEAD"`. It does not
  give an error. Graphs that used `CurrentBranch` or
  `BranchStatus.current_branch` keep a string.

  This runner does not talk to Git.

  ## Examples

      iex> input = %DomovoyGitPlugin.Runner.RepoBranch.Input{
      ...>   repo_state: %{
      ...>     path: "/repo",
      ...>     repo_root: "/repo",
      ...>     checkout: :main,
      ...>     worktree_name: nil,
      ...>     base_branch: nil,
      ...>     current_branch: "main",
      ...>     detached?: false,
      ...>     upstream_branch: "origin/main",
      ...>     ahead: 0,
      ...>     behind: 0,
      ...>     dirty?: false,
      ...>     operation: :idle,
      ...>     status: [],
      ...>     conflicts: []
      ...>   }
      ...> }
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "repo_branch"}
      iex> DomovoyGitPlugin.Runner.RepoBranch.run(input, context)
      {:ok, "main"}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  input do
    field(:repo_state, RepoStateType)
  end

  required([:repo_state])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{repo_state: %{detached?: true}}, %Context{}), do: {:ok, "HEAD"}
  def run(%Input{repo_state: %{current_branch: branch}}, %Context{}), do: {:ok, branch}
end
