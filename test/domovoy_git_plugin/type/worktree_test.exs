defmodule DomovoyGitPlugin.Type.WorktreeTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Type.Worktree, as: WorktreeType

  @worktree %{
    repo_root: "/repo",
    name: "bro-50",
    path: "/repo/.worktrees/bro-50",
    exists?: true,
    created?: false,
    branch: "bro-50"
  }

  describe "cast/2" do
    test "accepts a worktree on a branch" do
      assert WorktreeType.cast(@worktree, %{}) == {:ok, @worktree}
    end

    test "accepts a detached worktree and an optional base branch" do
      detached = %{@worktree | branch: nil}
      with_base = Map.put(@worktree, :base_branch, "main")

      assert WorktreeType.cast(detached, %{}) == {:ok, detached}
      assert WorktreeType.cast(with_base, %{}) == {:ok, with_base}
    end

    test "refuses a worktree with a missing or malformed field" do
      assert WorktreeType.cast(Map.delete(@worktree, :path), %{}) == :error
      assert WorktreeType.cast(%{@worktree | exists?: "yes"}, %{}) == :error
      assert WorktreeType.cast(%{@worktree | branch: :main}, %{}) == :error
      assert WorktreeType.cast("/repo/.worktrees/bro-50", %{}) == :error
      assert WorktreeType.cast(nil, %{}) == :error
    end
  end

  describe "Ecto.Type" do
    test "is stored as a map" do
      assert WorktreeType.type() == :map
      assert WorktreeType.cast(@worktree) == {:ok, @worktree}
      assert {:ok, document} = WorktreeType.dump(@worktree)
      assert WorktreeType.load(document) == {:ok, @worktree}
    end
  end
end
