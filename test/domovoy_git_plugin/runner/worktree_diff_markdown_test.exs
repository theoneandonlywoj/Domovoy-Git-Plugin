defmodule DomovoyGitPlugin.Runner.WorktreeDiffMarkdownTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Capabilities.WorktreeMetadata
  alias DomovoyGitPlugin.Runner.WorktreeDiffMarkdown
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.Worktree, as: WorktreeType

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

    {:ok, worktree_path: path, worktree: worktree}
  end

  describe "run/2" do
    test "renders the changes of the worktree as Markdown", %{
      worktree: worktree,
      worktree_path: path
    } do
      File.write!(Path.join(path, "README.md"), "changed\n")

      assert %Value{value: markdown, type: StringType} =
               NodeRunner.run(build_node(), [{"find_worktree", worktree}])

      assert markdown =~ "# Worktree feature"
      assert markdown =~ "- Branch: `feature`"
      assert markdown =~ "- Base branch: `main`"
      assert markdown =~ "- Path: `#{path}`"
      assert markdown =~ "## README.md"
      assert markdown =~ "```diff"
      assert markdown =~ "+changed"
    end

    test "renders a worktree without changes", %{worktree: worktree} do
      assert %Value{value: markdown} = NodeRunner.run(build_node(), [{"find_worktree", worktree}])
      assert markdown =~ "_No changes._"
    end

    test "a base_branch argument overrides the base branch of the worktree", %{
      worktree: worktree
    } do
      node = build_node(%{base_branch: {"feature", StringType}})

      assert %Value{value: markdown} = NodeRunner.run(node, [{"find_worktree", worktree}])
      assert markdown =~ "- Base branch: `feature`"
    end

    test "reports a worktree with no base branch and none supplied", %{worktree: worktree} do
      worktree = Value.cast!(%{worktree.value | base_branch: nil}, WorktreeType)

      assert %Error{} = error = NodeRunner.run(build_node(), [{"find_worktree", worktree}])
      assert error.type == :git_worktree_diff_failed
      assert error.metadata == %{node_name: "worktree_diff", field_name: :base_branch}
    end
  end

  @spec build_node(args :: map()) :: Node.t()
  defp build_node(args \\ %{}) do
    Node.new(%{
      name: "worktree_diff",
      runner: WorktreeDiffMarkdown,
      type: StringType,
      bind: %{worktree: {"find_worktree", WorktreeType}},
      args: args
    })
  end
end
