defmodule DomovoyGitPlugin.Capabilities.DiffParserTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Capabilities.DiffParser

  doctest DiffParser

  describe "parse/1" do
    test "returns an empty list for text with no diff header" do
      assert DiffParser.parse("") == []
      assert DiffParser.parse("nothing to commit, working tree clean\n") == []
    end

    test "extracts the file, its hunk header, and its added and removed lines in order" do
      diff = """
      diff --git a/README.md b/README.md
      index 1234567..89abcde 100644
      --- a/README.md
      +++ b/README.md
      @@ -1,3 +1,4 @@ defmodule Example do
       context line
      -removed first
      -removed second
      +added first
      +added second
      """

      assert [file_diff] = DiffParser.parse(diff)
      assert file_diff.file == "README.md"
      assert [hunk] = file_diff.hunks
      assert hunk.header == "@@ -1,3 +1,4 @@ defmodule Example do"
      assert hunk.section == "defmodule Example do"
      assert hunk.added_lines == ["added first", "added second"]
      assert hunk.removed_lines == ["removed first", "removed second"]
    end

    test "computes end lines from the hunk counts" do
      diff = """
      diff --git a/lib/example.ex b/lib/example.ex
      @@ -10,5 +20,7 @@
      +added
      """

      assert [%{hunks: [hunk]}] = DiffParser.parse(diff)
      assert hunk.old_start_line == 10
      assert hunk.old_end_line == 14
      assert hunk.new_start_line == 20
      assert hunk.new_end_line == 26
    end

    test "gives no old line numbers for an added file" do
      diff = """
      diff --git a/lib/new.ex b/lib/new.ex
      new file mode 100644
      --- /dev/null
      +++ b/lib/new.ex
      @@ -0,0 +1,3 @@
      +added
      """

      assert [%{hunks: [hunk]}] = DiffParser.parse(diff)
      assert hunk.old_start_line == nil
      assert hunk.old_end_line == nil
      assert hunk.new_start_line == 1
      assert hunk.new_end_line == 3
    end

    test "gives no new line numbers for a deleted file" do
      diff = """
      diff --git a/lib/old.ex b/lib/old.ex
      deleted file mode 100644
      --- a/lib/old.ex
      +++ /dev/null
      @@ -1,3 +0,0 @@
      -removed
      """

      assert [%{hunks: [hunk]}] = DiffParser.parse(diff)
      assert hunk.old_start_line == 1
      assert hunk.old_end_line == 3
      assert hunk.new_start_line == nil
      assert hunk.new_end_line == nil
    end

    test "treats an omitted hunk count as one line" do
      diff = """
      diff --git a/lib/example.ex b/lib/example.ex
      @@ -3 +7 @@
      +added
      """

      assert [%{hunks: [hunk]}] = DiffParser.parse(diff)
      assert hunk.old_start_line == 3
      assert hunk.old_end_line == 3
      assert hunk.new_start_line == 7
      assert hunk.new_end_line == 7
    end

    test "reports a missing section as nil" do
      diff = """
      diff --git a/lib/example.ex b/lib/example.ex
      @@ -1,1 +1,1 @@
      +added
      """

      assert [%{hunks: [%{section: nil}]}] = DiffParser.parse(diff)
    end

    test "keeps every file and every hunk, in the order the diff lists them" do
      diff = """
      diff --git a/first.ex b/first.ex
      @@ -1,1 +1,1 @@
      +first change
      @@ -10,1 +10,1 @@
      +second change
      diff --git a/second.ex b/second.ex
      @@ -1,1 +1,1 @@
      -only removal
      """

      assert [first, second] = DiffParser.parse(diff)
      assert first.file == "first.ex"

      assert Enum.map(first.hunks, fn hunk -> hunk.added_lines end) == [
               ["first change"],
               ["second change"]
             ]

      assert second.file == "second.ex"
      assert [%{added_lines: [], removed_lines: ["only removal"]}] = second.hunks
    end

    test "reports a file with no hunks, as a mode change produces" do
      diff = """
      diff --git a/script.sh b/script.sh
      old mode 100644
      new mode 100755
      """

      assert DiffParser.parse(diff) == [%{file: "script.sh", hunks: []}]
    end

    test "takes the post-image path for a rename" do
      diff = """
      diff --git a/old_name.ex b/new_name.ex
      similarity index 95%
      rename from old_name.ex
      rename to new_name.ex
      """

      assert [%{file: "new_name.ex"}] = DiffParser.parse(diff)
    end

    test "handles a path containing spaces" do
      diff = """
      diff --git a/docs/my notes.md b/docs/my notes.md
      @@ -1,1 +1,1 @@
      +note
      """

      assert [%{file: "docs/my notes.md"}] = DiffParser.parse(diff)
    end

    test "ignores +++ and --- headers rather than reading them as changed lines" do
      diff = """
      diff --git a/README.md b/README.md
      --- a/README.md
      +++ b/README.md
      @@ -1,1 +1,1 @@
      +real addition
      """

      assert [%{hunks: [hunk]}] = DiffParser.parse(diff)
      assert hunk.added_lines == ["real addition"]
      assert hunk.removed_lines == []
    end

    test "ignores changed lines appearing before any hunk header" do
      diff = """
      diff --git a/README.md b/README.md
      +stray line outside a hunk
      """

      assert DiffParser.parse(diff) == [%{file: "README.md", hunks: []}]
    end
  end
end
