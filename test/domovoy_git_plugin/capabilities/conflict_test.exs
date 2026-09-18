defmodule DomovoyGitPlugin.Capabilities.ConflictTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Capabilities.Conflict

  doctest Conflict

  describe "kind/1" do
    test "names each porcelain pair" do
      assert Conflict.kind("UU") == :both_modified
      assert Conflict.kind("AA") == :both_added
      assert Conflict.kind("DD") == :both_deleted
      assert Conflict.kind("AU") == :added_by_us
      assert Conflict.kind("UA") == :added_by_them
      assert Conflict.kind("DU") == :deleted_by_us
      assert Conflict.kind("UD") == :deleted_by_them
      assert Conflict.kind("UX") == :unknown
    end
  end

  describe "unmerged?/1" do
    test "accepts U in either position and the AA and DD pairs" do
      assert Conflict.unmerged?("UU")
      assert Conflict.unmerged?("AU")
      assert Conflict.unmerged?("UA")
      assert Conflict.unmerged?("AA")
      assert Conflict.unmerged?("DD")
      assert Conflict.unmerged?(%{code: "DU"})
      refute Conflict.unmerged?(" M")
      refute Conflict.unmerged?("??")
    end
  end

  describe "parse_stages/1" do
    test "groups stages by path and fills missing sides with nil" do
      output = """
      100644 aaa 1\tlib/a.ex
      100644 bbb 2\tlib/a.ex
      100644 ccc 3\tlib/a.ex
      100644 ddd 2\tonly-ours.ex
      """

      assert Conflict.parse_stages(output) == %{
               "lib/a.ex" => %{
                 base: %{mode: "100644", oid: "aaa"},
                 ours: %{mode: "100644", oid: "bbb"},
                 theirs: %{mode: "100644", oid: "ccc"}
               },
               "only-ours.ex" => %{
                 base: nil,
                 ours: %{mode: "100644", oid: "ddd"},
                 theirs: nil
               }
             }
    end

    test "drops lines it does not understand" do
      assert Conflict.parse_stages("not a stage line\n") == %{}
    end
  end

  describe "parse_hunks/1" do
    test "parses two hunks and drops leftover text" do
      text = """
      preamble
      <<<<<<< HEAD
      first ours
      =======
      first theirs
      >>>>>>> feature
      between
      <<<<<<< HEAD
      second ours
      =======
      second theirs
      >>>>>>> other
      trailing
      """

      assert [
               %{
                 ours: ["first ours"],
                 theirs: ["first theirs"],
                 ancestor_label: nil,
                 ours_label: "HEAD",
                 theirs_label: "feature"
               },
               %{
                 ours: ["second ours"],
                 theirs: ["second theirs"],
                 ancestor_label: nil,
                 ours_label: "HEAD",
                 theirs_label: "other"
               }
             ] = Conflict.parse_hunks(text)
    end

    test "drops an incomplete hunk" do
      text = """
      <<<<<<< HEAD
      ours
      =======
      theirs
      """

      assert Conflict.parse_hunks(text) == []
    end

    test "keeps empty sides and nil labels" do
      text = """
      <<<<<<<
      =======
      >>>>>>>
      """

      assert [
               %{
                 ours: [],
                 theirs: [],
                 ancestor_label: nil,
                 ours_label: nil,
                 theirs_label: nil
               }
             ] = Conflict.parse_hunks(text)
    end

    test "restarts when a new start marker appears mid-hunk" do
      text = """
      <<<<<<< HEAD
      stale
      <<<<<<< ours
      kept
      =======
      other
      >>>>>>> theirs
      """

      assert [
               %{
                 ours: ["kept"],
                 theirs: ["other"],
                 ours_label: "ours",
                 theirs_label: "theirs"
               }
             ] = Conflict.parse_hunks(text)
    end
  end

  describe "hunks_from_file/1" do
    @describetag :tmp_dir

    test "gives an empty list for a missing file", %{tmp_dir: directory} do
      assert Conflict.hunks_from_file(Path.join(directory, "missing.txt")) == []
    end

    test "gives an empty list for a binary file", %{tmp_dir: directory} do
      path = Path.join(directory, "blob.bin")
      File.write!(path, <<0, 1, 2, 255>>)

      assert Conflict.hunks_from_file(path) == []
    end

    test "parses markers from a text file", %{tmp_dir: directory} do
      path = Path.join(directory, "conflict.txt")

      File.write!(path, """
      <<<<<<< HEAD
      a
      =======
      b
      >>>>>>> feature
      """)

      assert [%{ours: ["a"], theirs: ["b"]}] = Conflict.hunks_from_file(path)
    end
  end

  describe "kinds/0" do
    test "holds every kind that kind/1 gives" do
      assert Enum.sort(Conflict.kinds()) ==
               Enum.sort([
                 :both_modified,
                 :both_added,
                 :both_deleted,
                 :added_by_us,
                 :added_by_them,
                 :deleted_by_us,
                 :deleted_by_them,
                 :unknown
               ])
    end
  end
end
