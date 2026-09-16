defmodule DomovoyGitPlugin.Type.StatusEntriesTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Type.StatusEntries, as: StatusEntriesType

  describe "cast/2" do
    test "wraps a list of entries" do
      entries = [
        %{path: "README.md", code: " M", index: :unmodified, worktree: :modified},
        %{path: "notes.txt", code: "??", index: :untracked, worktree: :untracked}
      ]

      assert {:ok, ^entries} = StatusEntriesType.cast(entries, %{})
    end

    test "wraps an empty list, which means the tree is clean" do
      assert {:ok, []} = StatusEntriesType.cast([], %{})
    end

    test "keeps a rename entry's arrow notation as the path" do
      entries = [
        %{path: "old.ex -> new.ex", code: "R ", index: :renamed, worktree: :unmodified}
      ]

      assert {:ok, ^entries} = StatusEntriesType.cast(entries, %{})
    end

    test "rejects a value that is not a list" do
      assert :error =
               StatusEntriesType.cast(
                 %{path: "a", code: " M", index: :unmodified, worktree: :modified},
                 []
               )

      assert :error = StatusEntriesType.cast(" M README.md", %{})
    end

    test "rejects entries missing a key, holding a bad state, or holding a blank path" do
      assert :error = StatusEntriesType.cast([%{code: " M"}], %{})
      assert :error = StatusEntriesType.cast([%{path: "README.md"}], %{})

      assert :error =
               StatusEntriesType.cast(
                 [%{path: "a", code: " M", index: :unmodified}],
                 []
               )

      assert :error =
               StatusEntriesType.cast(
                 [%{path: "a", code: " M", index: " ", worktree: :modified}],
                 []
               )

      assert :error =
               StatusEntriesType.cast(
                 [%{path: "a", code: " M", index: :unmodified, worktree: :sideways}],
                 []
               )

      assert :error =
               StatusEntriesType.cast(
                 [%{path: "", code: " M", index: :unmodified, worktree: :modified}],
                 []
               )
    end
  end

  describe "dump/1" do
    test "returns the entries" do
      entries = [%{path: "lib/example.ex", code: "A ", index: :added, worktree: :unmodified}]

      assert {:ok, document} = StatusEntriesType.dump(entries)
      assert StatusEntriesType.load(document) == {:ok, entries}
    end
  end
end
