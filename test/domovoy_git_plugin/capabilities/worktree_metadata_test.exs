defmodule DomovoyGitPlugin.Capabilities.WorktreeMetadataTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Capabilities.WorktreeMetadata

  # Only the pure functions are doctested; the record readers and writers touch
  # the filesystem, so their moduledoc examples stay illustrative.
  doctest WorktreeMetadata,
    only: [
      worktree_path: 2,
      worktrees_root: 1,
      main_root: 1,
      parse_porcelain: 1,
      parse_repository: 2,
      record_path: 2
    ]

  describe "parse_porcelain/1" do
    test "returns one record per worktree block" do
      output = """
      worktree /repo
      HEAD abc123
      branch refs/heads/main

      worktree /repo/.worktrees/feature
      HEAD def456
      branch refs/heads/feature
      """

      assert [main, feature] = WorktreeMetadata.parse_porcelain(output)
      assert main == %{path: "/repo", head: "abc123", branch: "main"}
      assert feature.path == "/repo/.worktrees/feature"
      assert feature.branch == "feature"
    end

    test "reports a detached worktree with a nil branch" do
      output = """
      worktree /repo/.worktrees/detached
      HEAD abc123
      detached
      """

      assert [%{branch: nil, head: "abc123"}] = WorktreeMetadata.parse_porcelain(output)
    end

    test "ignores bare, locked, and prunable lines" do
      output = """
      worktree /repo
      HEAD abc123
      branch refs/heads/main
      locked
      prunable gitdir file points to non-existent location
      """

      assert [%{path: "/repo", branch: "main"}] = WorktreeMetadata.parse_porcelain(output)
    end

    test "skips a block with no worktree line" do
      assert WorktreeMetadata.parse_porcelain("HEAD abc123\nbranch refs/heads/main\n") == []
      assert WorktreeMetadata.parse_porcelain("") == []
    end
  end

  describe "parse_repository/2" do
    test "expands the common dir against the working directory, not the root" do
      assert {:ok, repository} = WorktreeMetadata.parse_repository("/repo\n.git\n", "/repo/lib")
      assert repository.root == "/repo"
      assert repository.git_common_directory == "/repo/lib/.git"
    end

    test "returns :error when Git named fewer than two paths" do
      assert WorktreeMetadata.parse_repository("/repo\n", "/repo") == :error
      assert WorktreeMetadata.parse_repository("", "/repo") == :error
    end
  end

  describe "main_root/1" do
    test "returns the first record's path, which Git always reports first" do
      records = [%{path: "/repo", head: nil, branch: nil}, %{path: "/wt", head: nil, branch: nil}]

      assert WorktreeMetadata.main_root(records) == "/repo"
    end
  end

  describe "worktree_path/2 and worktrees_root/1" do
    test "place managed worktrees under .worktrees" do
      assert WorktreeMetadata.worktrees_root("/repo") == "/repo/.worktrees"
      assert WorktreeMetadata.worktree_path("/repo", "feature") == "/repo/.worktrees/feature"
    end
  end

  describe "record_path/2, write_record/3, read_base_branch/2, delete_record/2" do
    test "round-trips a base branch through the record file" do
      git_common_directory = temporary_directory!()

      assert WorktreeMetadata.record_path(git_common_directory, "feature") ==
               Path.join([git_common_directory, "domovoy", "worktrees", "feature.json"])

      assert :ok =
               WorktreeMetadata.write_record(git_common_directory, "feature", %{
                 path: "/repo/.worktrees/feature",
                 branch: "feature",
                 base_branch: "main"
               })

      assert WorktreeMetadata.read_base_branch(git_common_directory, "feature") == "main"
    end

    test "reports a missing record as nil rather than an error" do
      assert WorktreeMetadata.read_base_branch(temporary_directory!(), "absent") == nil
    end

    test "reports an undecodable or incomplete record as nil" do
      git_common_directory = temporary_directory!()
      path = WorktreeMetadata.record_path(git_common_directory, "broken")
      File.mkdir_p!(Path.dirname(path))

      File.write!(path, "{not json")
      assert WorktreeMetadata.read_base_branch(git_common_directory, "broken") == nil

      File.write!(path, ~s({"worktree_name":"broken"}))
      assert WorktreeMetadata.read_base_branch(git_common_directory, "broken") == nil
    end

    test "deletes a record and succeeds when none exists" do
      git_common_directory = temporary_directory!()

      :ok =
        WorktreeMetadata.write_record(git_common_directory, "feature", %{
          path: "/repo/.worktrees/feature",
          branch: "feature",
          base_branch: "main"
        })

      assert WorktreeMetadata.delete_record(git_common_directory, "feature") == :ok
      assert WorktreeMetadata.read_base_branch(git_common_directory, "feature") == nil
      assert WorktreeMetadata.delete_record(git_common_directory, "feature") == :ok
    end
  end

  @spec temporary_directory!() :: String.t()
  defp temporary_directory! do
    path = Path.join(System.tmp_dir!(), "domovoy-wtmeta-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)

    path
  end
end
