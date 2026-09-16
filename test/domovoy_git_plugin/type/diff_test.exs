defmodule DomovoyGitPlugin.Type.DiffTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Type.Diff, as: DiffType

  describe "cast/2" do
    test "wraps a parsed diff" do
      file_diffs = [%{file: "README.md", hunks: [hunk()]}]

      assert {:ok, ^file_diffs} = DiffType.cast(file_diffs, %{})
    end

    test "wraps an empty diff, which means the trees are identical" do
      assert {:ok, []} = DiffType.cast([], %{})
    end

    test "wraps a file carrying no hunks, as a mode change produces" do
      assert {:ok, _} = DiffType.cast([%{file: "script.sh", hunks: []}], %{})
    end

    test "rejects a value that is not a list" do
      assert :error = DiffType.cast(%{file: "README.md", hunks: []}, %{})
      assert :error = DiffType.cast("diff --git a/a b/a", %{})
      assert :error = DiffType.cast(nil, %{})
    end

    test "rejects entries missing the file or hunks keys" do
      assert :error = DiffType.cast([%{file: "README.md"}], %{})
      assert :error = DiffType.cast([%{hunks: []}], %{})
      assert :error = DiffType.cast([%{file: :readme, hunks: []}], %{})
    end

    test "rejects a hunk missing its line lists or header" do
      assert :error = DiffType.cast([%{file: "a.ex", hunks: [%{header: "@@"}]}], %{})

      malformed = Map.delete(hunk(), :added_lines)
      assert :error = DiffType.cast([%{file: "a.ex", hunks: [malformed]}], %{})
    end

    test "records this module on the error and not the rejected value" do
      assert DomovoyCore.Value.cast("nope", DiffType) ==
               {:error, %DomovoyCore.Error{type: :cast_error, reason: %{module: DiffType}}}
    end
  end

  describe "dump/1" do
    test "returns the parsed diff" do
      file_diffs = [%{file: "README.md", hunks: []}]

      assert {:ok, document} = DiffType.dump(file_diffs)
      assert DiffType.load(document) == {:ok, file_diffs}
    end
  end

  @spec hunk() :: map()
  defp hunk do
    %{
      header: "@@ -1,1 +1,1 @@",
      old_start_line: 1,
      old_end_line: 1,
      new_start_line: 1,
      new_end_line: 1,
      section: nil,
      added_lines: ["added"],
      removed_lines: []
    }
  end
end
