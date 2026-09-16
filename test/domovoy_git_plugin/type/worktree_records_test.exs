defmodule DomovoyGitPlugin.Type.WorktreeRecordsTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Type.WorktreeRecords, as: WorktreeRecordsType

  describe "cast/2" do
    test "wraps a listing of the main checkout and a linked worktree" do
      worktrees = [worktree(%{worktree_name: nil, main?: true}), worktree(%{})]

      assert {:ok, ^worktrees} = WorktreeRecordsType.cast(worktrees, %{})
    end

    test "accepts a nil branch, head, and base_branch" do
      state = worktree(%{branch: nil, head: nil, base_branch: nil})

      assert {:ok, _} = WorktreeRecordsType.cast([state], %{})
    end

    test "accepts an empty listing" do
      assert {:ok, []} = WorktreeRecordsType.cast([], %{})
    end

    test "rejects a value that is not a list" do
      assert :error = WorktreeRecordsType.cast(worktree(%{}), %{})
    end

    test "rejects a blank path, a non-boolean main?, and a non-string worktree_name" do
      assert :error = WorktreeRecordsType.cast([worktree(%{path: ""})], %{})
      assert :error = WorktreeRecordsType.cast([worktree(%{main?: "yes"})], %{})
      assert :error = WorktreeRecordsType.cast([worktree(%{worktree_name: :feature})], %{})
    end

    test "rejects an entry missing a required key" do
      assert :error = WorktreeRecordsType.cast([%{path: "/repo"}], %{})
    end
  end

  describe "dump/1" do
    test "returns the listing" do
      worktrees = [worktree(%{})]

      assert {:ok, document} = WorktreeRecordsType.dump(worktrees)
      assert WorktreeRecordsType.load(document) == {:ok, worktrees}
    end
  end

  @spec worktree(map()) :: map()
  defp worktree(overrides) do
    Map.merge(
      %{
        worktree_name: "feature",
        path: "/repo/.worktrees/feature",
        branch: "feature",
        head: "abc123",
        base_branch: "main",
        main?: false
      },
      overrides
    )
  end
end
