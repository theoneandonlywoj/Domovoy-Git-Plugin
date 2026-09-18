defmodule DomovoyGitPlugin.Runner.RepoConflictsTest do
  use ExUnit.Case, async: true

  alias DomovoyCore.Node
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.RepoConflicts
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Type.Conflicts, as: ConflictsType
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  doctest RepoConflicts

  describe "run/2" do
    test "returns the conflicts list from the snapshot" do
      assert %Value{value: [], type: ConflictsType} =
               NodeRunner.run(build_node(), [{"repo_state", state()}])
    end
  end

  @spec build_node() :: Node.t()
  defp build_node do
    Node.new(%{
      name: "repo_conflicts",
      runner: RepoConflicts,
      type: ConflictsType,
      bind: %{repo_state: {"repo_state", RepoStateType}}
    })
  end

  @spec state() :: Value.t()
  defp state do
    Value.cast!(
      %{
        path: "/repo",
        repo_root: "/repo",
        checkout: :main,
        worktree_name: nil,
        base_branch: nil,
        current_branch: "main",
        detached?: false,
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
