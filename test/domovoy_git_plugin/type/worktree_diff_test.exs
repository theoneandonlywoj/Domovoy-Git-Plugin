defmodule DomovoyGitPlugin.Type.WorktreeDiffTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Type.WorktreeDiff, as: WorktreeDiffType

  describe "cast/2" do
    test "wraps a worktree diff" do
      state = diff(%{})

      assert {:ok, ^state} = WorktreeDiffType.cast(state, %{})
    end

    test "accepts an empty file list and a nil branch" do
      assert {:ok, _} = WorktreeDiffType.cast(diff(%{files: []}), %{})
      assert {:ok, _} = WorktreeDiffType.cast(diff(%{branch: nil}), %{})
    end

    test "rejects a blank worktree name or base branch" do
      assert :error = WorktreeDiffType.cast(diff(%{worktree_name: ""}), %{})
      assert :error = WorktreeDiffType.cast(diff(%{base_branch: ""}), %{})
      assert :error = WorktreeDiffType.cast(diff(%{base_branch: nil}), %{})
    end

    test "rejects a non-list files field and a map missing a key" do
      assert :error = WorktreeDiffType.cast(diff(%{files: %{}}), %{})
      assert :error = WorktreeDiffType.cast(%{worktree_name: "feature"}, %{})
    end
  end

  describe "dump/1" do
    test "returns the worktree diff" do
      state = diff(%{})

      assert {:ok, document} = WorktreeDiffType.dump(state)
      assert WorktreeDiffType.load(document) == {:ok, state}
    end
  end

  @spec diff(map()) :: map()
  defp diff(overrides) do
    Map.merge(
      %{
        worktree_name: "feature",
        path: "/repo/.worktrees/feature",
        branch: "feature",
        base_branch: "main",
        files: [%{file: "README.md", hunks: []}]
      },
      overrides
    )
  end
end
