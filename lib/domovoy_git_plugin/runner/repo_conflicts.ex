defmodule DomovoyGitPlugin.Runner.RepoConflicts do
  @moduledoc """
  Returns the conflicts list from a `RepoState`.

  An empty list means there are no unmerged paths. This runner does not talk to
  Git.

  ## Examples

      iex> input = %DomovoyGitPlugin.Runner.RepoConflicts.Input{
      ...>   repo_state: %{
      ...>     path: "/repo",
      ...>     repo_root: "/repo",
      ...>     checkout: :main,
      ...>     worktree_name: nil,
      ...>     base_branch: nil,
      ...>     current_branch: "main",
      ...>     detached?: false,
      ...>     upstream_branch: nil,
      ...>     ahead: nil,
      ...>     behind: nil,
      ...>     dirty?: false,
      ...>     operation: :idle,
      ...>     status: [],
      ...>     conflicts: []
      ...>   }
      ...> }
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "repo_conflicts"}
      iex> DomovoyGitPlugin.Runner.RepoConflicts.run(input, context)
      {:ok, []}
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
  def run(%Input{repo_state: %{conflicts: conflicts}}, %Context{}), do: {:ok, conflicts}
end
