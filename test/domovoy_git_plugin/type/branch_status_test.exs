defmodule DomovoyGitPlugin.Type.BranchStatusTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Type.BranchStatus, as: BranchStatusType

  describe "cast/2" do
    test "wraps a branch status with an upstream" do
      state = state(%{upstream_branch: "origin/main"})

      assert {:ok, ^state} = BranchStatusType.cast(state, %{})
    end

    test "accepts a nil upstream, which a branch that was never pushed has" do
      assert {:ok, _} = BranchStatusType.cast(state(%{upstream_branch: nil}), %{})
    end

    test "accepts an empty status list, which a clean tree has" do
      assert {:ok, _} = BranchStatusType.cast(state(%{status: []}), %{})
    end

    test "rejects a blank or non-string current branch" do
      assert :error = BranchStatusType.cast(state(%{current_branch: ""}), %{})
      assert :error = BranchStatusType.cast(state(%{current_branch: nil}), %{})
    end

    test "rejects a non-string, non-nil upstream and a non-list status" do
      assert :error = BranchStatusType.cast(state(%{upstream_branch: :origin}), %{})
      assert :error = BranchStatusType.cast(state(%{status: %{}}), %{})
    end

    test "rejects a map missing a key entirely" do
      assert :error = BranchStatusType.cast(%{current_branch: "main"}, %{})
      assert :error = BranchStatusType.cast("main", %{})
    end
  end

  describe "dump/1" do
    test "returns the branch status" do
      state = state(%{})

      assert {:ok, document} = BranchStatusType.dump(state)
      assert BranchStatusType.load(document) == {:ok, state}
    end
  end

  @spec state(map()) :: map()
  defp state(overrides) do
    Map.merge(
      %{
        current_branch: "main",
        upstream_branch: "origin/main",
        status: [%{path: "README.md", code: " M", index: :unmodified, worktree: :modified}]
      },
      overrides
    )
  end
end
