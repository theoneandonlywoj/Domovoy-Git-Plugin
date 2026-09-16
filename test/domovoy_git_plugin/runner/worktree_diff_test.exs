defmodule DomovoyGitPlugin.Runner.WorktreeDiffTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Capabilities.WorktreeMetadata
  alias DomovoyGitPlugin.Runner.WorktreeDiff
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.Worktree, as: WorktreeType
  alias DomovoyGitPlugin.Type.WorktreeDiff, as: WorktreeDiffType

  setup do
    repository = Repository.create!(remote?: false)
    on_exit(fn -> File.rm_rf(repository.parent) end)

    path = WorktreeMetadata.worktree_path(repository.root, "feature")
    Repository.git!(["-C", repository.root, "worktree", "add", "-q", "-b", "feature", path])

    worktree =
      Value.cast!(
        %{
          repo_root: repository.root,
          name: "feature",
          path: path,
          exists?: true,
          created?: false,
          branch: "feature",
          base_branch: "main"
        },
        WorktreeType
      )

    {:ok, repository: repository, worktree_path: path, worktree: worktree}
  end

  describe "run/2" do
    test "covers commits, staged, and unstaged changes in one diff", %{
      worktree: worktree,
      worktree_path: path
    } do
      File.write!(Path.join(path, "committed.txt"), "committed\n")
      Repository.git!(["-C", path, "add", "committed.txt"])
      Repository.git!(["-C", path, "commit", "-qm", "work"])

      File.write!(Path.join(path, "staged.txt"), "staged\n")
      Repository.git!(["-C", path, "add", "staged.txt"])
      File.write!(Path.join(path, "README.md"), "unstaged\n")

      assert %Value{value: diff, type: WorktreeDiffType} =
               NodeRunner.run(build_node(), [{"find_worktree", worktree}])

      files = Enum.map(diff.files, fn file_diff -> file_diff.file end)
      assert "committed.txt" in files
      assert "staged.txt" in files
      assert "README.md" in files
    end

    test "includes untracked files", %{worktree: worktree, worktree_path: path} do
      File.write!(Path.join(path, "loose.txt"), "untracked\n")

      assert %Value{value: diff} = NodeRunner.run(build_node(), [{"find_worktree", worktree}])
      assert Enum.any?(diff.files, fn file_diff -> file_diff.file == "loose.txt" end)
    end

    test "carries the identity of the worktree alongside the files", %{
      worktree: worktree,
      worktree_path: path
    } do
      assert %Value{value: diff} = NodeRunner.run(build_node(), [{"find_worktree", worktree}])
      assert diff.worktree_name == "feature"
      assert diff.path == path
      assert diff.branch == "feature"
      assert diff.base_branch == "main"
      assert diff.files == []
    end

    test "uses the base branch of the worktree when none is supplied", %{worktree: worktree} do
      assert %Value{value: %{base_branch: "main"}} =
               NodeRunner.run(build_node(), [{"find_worktree", worktree}])
    end

    test "a base_branch argument overrides the base branch of the worktree", %{
      worktree: worktree
    } do
      node = build_node(%{base_branch: {"feature", StringType}})

      assert %Value{value: %{base_branch: "feature"}} =
               NodeRunner.run(node, [{"find_worktree", worktree}])
    end

    test "takes the base branch from a bound node", %{worktree: worktree} do
      node =
        Node.new(%{
          name: "worktree_diff",
          runner: WorktreeDiff,
          type: WorktreeDiffType,
          bind: %{
            worktree: {"find_worktree", WorktreeType},
            base_branch: {"base_branch", StringType}
          }
        })

      base_branch = Value.cast!("feature", StringType)

      assert %Value{value: %{base_branch: "feature"}} =
               NodeRunner.run(node, [{"find_worktree", worktree}, {"base_branch", base_branch}])
    end

    test "reports a worktree with no base branch and none supplied", %{worktree: worktree} do
      worktree = Value.cast!(%{worktree.value | base_branch: nil}, WorktreeType)

      assert %Error{} = error = NodeRunner.run(build_node(), [{"find_worktree", worktree}])
      assert error.type == :git_worktree_diff_failed
      assert error.reason =~ "no recorded base branch"
      assert error.metadata == %{node_name: "worktree_diff", field_name: :base_branch}
    end

    test "reports an unknown base branch as a Git command failure", %{worktree: worktree} do
      node = build_node(%{base_branch: {"does-not-exist", StringType}})

      assert %Error{} = error = NodeRunner.run(node, [{"find_worktree", worktree}])
      assert error.type == :git_command_failed
      assert error.metadata[:field_name] == :worktree
    end

    test "refuses a node that binds no worktree" do
      assert_raise ArgumentError, ~r/required_input.*worktree/, fn ->
        Node.new(%{name: "worktree_diff", runner: WorktreeDiff, type: WorktreeDiffType})
      end
    end
  end

  @spec build_node(args :: map()) :: Node.t()
  defp build_node(args \\ %{}) do
    Node.new(%{
      name: "worktree_diff",
      runner: WorktreeDiff,
      type: WorktreeDiffType,
      bind: %{worktree: {"find_worktree", WorktreeType}},
      args: args
    })
  end
end
