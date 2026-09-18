defmodule DomovoyGitPlugin.Runner.RepoStatusTest do
  use ExUnit.Case, async: true

  alias DomovoyCore.Node
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.RepoStatus
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType
  alias DomovoyGitPlugin.Type.StatusEntries, as: StatusEntriesType

  doctest RepoStatus

  describe "run/2" do
    test "returns the status entries from the snapshot" do
      entries = [%{path: "README.md", code: " M", index: :unmodified, worktree: :modified}]

      assert %Value{value: ^entries, type: StatusEntriesType} =
               NodeRunner.run(build_node(), [{"repo_state", state(entries)}])
    end
  end

  @spec build_node() :: Node.t()
  defp build_node do
    Node.new(%{
      name: "repo_status",
      runner: RepoStatus,
      type: StatusEntriesType,
      bind: %{repo_state: {"repo_state", RepoStateType}}
    })
  end

  @spec state([map()]) :: Value.t()
  defp state(status) do
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
        dirty?: status != [],
        operation: :idle,
        status: status,
        conflicts: []
      },
      RepoStateType
    )
  end
end
