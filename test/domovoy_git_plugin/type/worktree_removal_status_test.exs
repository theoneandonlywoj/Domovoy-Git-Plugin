defmodule DomovoyGitPlugin.Type.WorktreeRemovalStatusTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Type.WorktreeRemovalStatus, as: WorktreeRemovalStatusType

  describe "cast/2" do
    test "wraps a removal that also deleted the branch" do
      state = removal(%{branch_deleted?: true})

      assert {:ok, ^state} = WorktreeRemovalStatusType.cast(state, %{})
    end

    test "accepts a nil branch, which a detached worktree has" do
      assert {:ok, _} = WorktreeRemovalStatusType.cast(removal(%{branch: nil}), %{})
    end

    test "rejects removed?: false, since a failed removal is an error not a value" do
      assert :error = WorktreeRemovalStatusType.cast(removal(%{removed?: false}), %{})
    end

    test "rejects a blank worktree name and a non-boolean branch_deleted?" do
      assert :error = WorktreeRemovalStatusType.cast(removal(%{worktree_name: ""}), %{})
      assert :error = WorktreeRemovalStatusType.cast(removal(%{branch_deleted?: nil}), %{})
    end

    test "rejects a map missing a key and a non-map value" do
      assert :error = WorktreeRemovalStatusType.cast(%{worktree_name: "feature"}, %{})
      assert :error = WorktreeRemovalStatusType.cast("feature", %{})
    end
  end

  describe "dump/1" do
    test "returns the removal outcome" do
      state = removal(%{})

      assert {:ok, document} = WorktreeRemovalStatusType.dump(state)
      assert WorktreeRemovalStatusType.load(document) == {:ok, state}
    end
  end

  @spec removal(map()) :: map()
  defp removal(overrides) do
    Map.merge(
      %{
        worktree_name: "feature",
        path: "/repo/.worktrees/feature",
        branch: "feature",
        removed?: true,
        branch_deleted?: false
      },
      overrides
    )
  end
end
