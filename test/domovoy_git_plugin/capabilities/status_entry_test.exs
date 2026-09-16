defmodule DomovoyGitPlugin.Capabilities.StatusEntryTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Capabilities.StatusEntry

  doctest StatusEntry

  describe "parse/1" do
    test "reads an unstaged change" do
      assert StatusEntry.parse(" M README.md") == %{
               path: "README.md",
               code: " M",
               index: :unmodified,
               worktree: :modified
             }
    end

    test "reads a staged change" do
      assert StatusEntry.parse("A  lib/new.ex") == %{
               path: "lib/new.ex",
               code: "A ",
               index: :added,
               worktree: :unmodified
             }
    end

    test "reads an untracked path" do
      assert StatusEntry.parse("?? notes.txt") == %{
               path: "notes.txt",
               code: "??",
               index: :untracked,
               worktree: :untracked
             }
    end

    test "reads an ignored path" do
      assert %{index: :ignored, worktree: :ignored} = StatusEntry.parse("!! _build/")
    end

    test "reads a conflict as two states" do
      assert %{index: :unmerged, worktree: :unmerged} = StatusEntry.parse("UU lib/app.ex")
    end

    test "gives :unknown for a character it does not know" do
      assert %{index: :unknown, worktree: :unknown} = StatusEntry.parse("ZZ lib/app.ex")
    end

    test "keeps the path of a rename as Git writes it" do
      assert %{path: "old.ex -> new.ex", index: :renamed} =
               StatusEntry.parse("R  old.ex -> new.ex")
    end

    test "reads a copy" do
      assert %{path: "old.ex -> copy.ex", index: :copied, worktree: :unmodified} =
               StatusEntry.parse("C  old.ex -> copy.ex")
    end
  end

  describe "states/0" do
    test "holds every state that parse/1 gives" do
      assert Enum.sort(StatusEntry.states()) ==
               Enum.sort([
                 :unmodified,
                 :added,
                 :modified,
                 :deleted,
                 :renamed,
                 :copied,
                 :unmerged,
                 :untracked,
                 :ignored,
                 :unknown
               ])
    end
  end
end
