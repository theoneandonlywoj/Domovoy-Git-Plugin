defmodule DomovoyGitPlugin.Type.WorktreesTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Type.Worktrees, as: WorktreesType

  @worktrees %{repo_root: "/repo", paths: ["/repo", "/repo/.worktrees/bro-50"]}

  describe "cast/2" do
    test "accepts a repository root with a list of paths" do
      assert WorktreesType.cast(@worktrees, %{}) == {:ok, @worktrees}

      assert WorktreesType.cast(%{@worktrees | paths: []}, %{}) ==
               {:ok, %{@worktrees | paths: []}}
    end

    test "refuses a path that is not a string" do
      assert WorktreesType.cast(%{@worktrees | paths: ["/repo", nil]}, %{}) == :error
      assert WorktreesType.cast(%{@worktrees | paths: "/repo"}, %{}) == :error
    end

    test "refuses a missing repository root" do
      assert WorktreesType.cast(%{paths: ["/repo"]}, %{}) == :error
      assert WorktreesType.cast(%{@worktrees | repo_root: nil}, %{}) == :error
      assert WorktreesType.cast(["/repo"], %{}) == :error
    end
  end

  describe "Ecto.Type" do
    test "is stored as a map" do
      assert WorktreesType.type() == :map
      assert WorktreesType.cast(@worktrees) == {:ok, @worktrees}
      assert {:ok, document} = WorktreesType.dump(@worktrees)
      assert WorktreesType.load(document) == {:ok, @worktrees}
    end
  end
end
