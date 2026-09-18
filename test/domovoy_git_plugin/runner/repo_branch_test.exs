defmodule DomovoyGitPlugin.Runner.RepoBranchTest do
  use ExUnit.Case, async: true

  alias DomovoyCore.Node
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.RepoBranch
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  doctest RepoBranch

  describe "run/2" do
    test "returns the current branch" do
      assert %Value{value: "main", type: StringType} =
               NodeRunner.run(build_node(), [{"repo_state", state("main", false)}])
    end

    test "returns HEAD when the checkout is detached" do
      assert %Value{value: "HEAD"} =
               NodeRunner.run(build_node(), [{"repo_state", state(nil, true)}])
    end
  end

  @spec build_node() :: Node.t()
  defp build_node do
    Node.new(%{
      name: "repo_branch",
      runner: RepoBranch,
      type: StringType,
      bind: %{repo_state: {"repo_state", RepoStateType}}
    })
  end

  @spec state(String.t() | nil, boolean()) :: Value.t()
  defp state(current_branch, detached?) do
    Value.cast!(
      %{
        path: "/repo",
        repo_root: "/repo",
        checkout: :main,
        worktree_name: nil,
        base_branch: nil,
        current_branch: current_branch,
        detached?: detached?,
        upstream_branch: nil,
        ahead: nil,
        behind: nil,
        dirty?: false,
        operation: :idle,
        status: [],
        conflicts: []
      },
      RepoStateType
    )
  end
end
