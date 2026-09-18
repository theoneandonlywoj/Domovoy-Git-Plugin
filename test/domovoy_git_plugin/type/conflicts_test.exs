defmodule DomovoyGitPlugin.Type.ConflictsTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Type.Conflicts, as: ConflictsType

  describe "cast/2" do
    test "wraps a list of conflicts" do
      conflicts = [conflict(%{})]

      assert {:ok, ^conflicts} = ConflictsType.cast(conflicts, %{})
    end

    test "wraps an empty list, which means there are no unmerged paths" do
      assert {:ok, []} = ConflictsType.cast([], %{})
    end

    test "accepts nil stages and empty hunks" do
      conflicts = [
        conflict(%{
          stages: %{base: nil, ours: %{mode: "100644", oid: "aaa"}, theirs: nil},
          hunks: []
        })
      ]

      assert {:ok, ^conflicts} = ConflictsType.cast(conflicts, %{})
    end

    test "rejects a value that is not a list" do
      assert :error = ConflictsType.cast(conflict(%{}), %{})
      assert :error = ConflictsType.cast("UU", %{})
    end

    test "rejects a conflict missing a key, holding a bad kind, or holding a blank path" do
      assert :error = ConflictsType.cast([%{path: "a.ex"}], %{})
      assert :error = ConflictsType.cast([conflict(%{kind: :sideways})], %{})
      assert :error = ConflictsType.cast([conflict(%{path: ""})], %{})
      assert :error = ConflictsType.cast([conflict(%{stages: %{}})], %{})
    end
  end

  describe "dump/1" do
    test "round-trips a conflict through a document" do
      conflicts = [conflict(%{})]

      assert {:ok, document} = ConflictsType.dump(conflicts)
      assert ConflictsType.load(document) == {:ok, conflicts}
    end

    test "round-trips nil stages" do
      conflicts = [conflict(%{stages: %{base: nil, ours: nil, theirs: nil}, hunks: []})]

      assert {:ok, document} = ConflictsType.dump(conflicts)
      assert ConflictsType.load(document) == {:ok, conflicts}
    end
  end

  @spec conflict(map()) :: map()
  defp conflict(overrides) do
    Map.merge(
      %{
        path: "lib/a.ex",
        kind: :both_modified,
        code: "UU",
        stages: %{
          base: %{mode: "100644", oid: "aaa"},
          ours: %{mode: "100644", oid: "bbb"},
          theirs: %{mode: "100644", oid: "ccc"}
        },
        hunks: [
          %{
            ours: ["left"],
            theirs: ["right"],
            ancestor_label: nil,
            ours_label: "HEAD",
            theirs_label: "feature"
          }
        ]
      },
      overrides
    )
  end
end
