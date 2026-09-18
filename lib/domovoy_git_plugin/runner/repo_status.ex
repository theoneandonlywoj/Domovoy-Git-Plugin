defmodule DomovoyGitPlugin.Runner.RepoStatus do
  @moduledoc """
  Returns the status entries from a `RepoState`.

  This runner does not talk to Git.

  ## Examples

      iex> input = %DomovoyGitPlugin.Runner.RepoStatus.Input{
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
      ...>     dirty?: true,
      ...>     operation: :idle,
      ...>     status: [%{path: "README.md", code: " M", index: :unmodified, worktree: :modified}],
      ...>     conflicts: []
      ...>   }
      ...> }
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "repo_status"}
      iex> DomovoyGitPlugin.Runner.RepoStatus.run(input, context)
      {:ok, [%{path: "README.md", code: " M", index: :unmodified, worktree: :modified}]}
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
  def run(%Input{repo_state: %{status: status}}, %Context{}), do: {:ok, status}
end
