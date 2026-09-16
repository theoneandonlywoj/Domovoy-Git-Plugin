defmodule DomovoyGitPlugin.Runner.WorktreeListTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Capabilities.WorktreeMetadata
  alias DomovoyGitPlugin.Runner.WorktreeList
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.WorktreeRecords, as: WorktreeRecordsType

  setup do
    repository = Repository.create!(remote?: false)
    on_exit(fn -> File.rm_rf(repository.parent) end)

    {:ok, repository: repository}
  end

  describe "run/2" do
    test "reports a repository with no linked worktrees as its main checkout only", %{
      repository: repository
    } do
      node = build_node(repository.root)

      assert %Value{value: [main], type: WorktreeRecordsType} = NodeRunner.run(node, [])
      assert main.main? == true
      assert main.worktree_name == nil
      assert main.branch == "main"
      assert is_binary(main.head)
    end

    test "names each linked worktree after the last segment of its path", %{
      repository: repository
    } do
      add_worktree!(repository, "feature", ["-b", "feature"])

      node = build_node(repository.root)

      assert %Value{value: worktrees} = NodeRunner.run(node, [])
      assert [_main, feature] = worktrees
      assert feature.main? == false
      assert feature.worktree_name == "feature"
      assert feature.branch == "feature"
    end

    test "reports a detached worktree with a nil branch", %{repository: repository} do
      add_worktree!(repository, "detached", ["--detach"])

      node = build_node(repository.root)

      assert %Value{value: [_main, detached]} = NodeRunner.run(node, [])
      assert detached.worktree_name == "detached"
      assert detached.branch == nil
    end

    test "reports a worktree with no record as base_branch nil", %{repository: repository} do
      add_worktree!(repository, "feature", ["-b", "feature"])

      node = build_node(repository.root)

      assert %Value{value: [_main, feature]} = NodeRunner.run(node, [])
      assert feature.base_branch == nil
    end

    test "reads the base branch Domovoy recorded for a worktree", %{repository: repository} do
      add_worktree!(repository, "feature", ["-b", "feature"])
      git_common_directory = Path.join(repository.root, ".git")

      :ok =
        WorktreeMetadata.write_record(git_common_directory, "feature", %{
          path: WorktreeMetadata.worktree_path(repository.root, "feature"),
          branch: "feature",
          base_branch: "main"
        })

      node = build_node(repository.root)

      assert %Value{value: [_main, feature]} = NodeRunner.run(node, [])
      assert feature.base_branch == "main"
    end

    test "identifies the main checkout correctly when run from inside a linked worktree", %{
      repository: repository
    } do
      add_worktree!(repository, "feature", ["-b", "feature"])

      node = build_node(WorktreeMetadata.worktree_path(repository.root, "feature"))

      assert %Value{value: [main, feature]} = NodeRunner.run(node, [])
      assert main.main? == true
      assert main.worktree_name == nil
      assert feature.main? == false
      assert feature.worktree_name == "feature"
    end

    test "returns a contextual error when the directory is not a repository" do
      outside =
        Path.join(System.tmp_dir!(), "domovoy-plain-#{System.unique_integer([:positive])}")

      File.mkdir_p!(outside)
      on_exit(fn -> File.rm_rf(outside) end)

      assert %Error{} = error = NodeRunner.run(build_node(outside), [])
      assert error.type == :git_command_failed
      assert error.metadata[:node_name] == "worktree_list"
    end
  end

  @spec build_node(working_directory :: String.t()) :: Node.t()
  defp build_node(working_directory) do
    Node.new(%{
      name: "worktree_list",
      runner: WorktreeList,
      type: WorktreeRecordsType,
      args: %{working_directory: {working_directory, DirectoryType}}
    })
  end

  @spec add_worktree!(Repository.t(), String.t(), [String.t()]) :: String.t()
  defp add_worktree!(repository, name, args) do
    path = WorktreeMetadata.worktree_path(repository.root, name)
    Repository.git!(["-C", repository.root, "worktree", "add", "-q"] ++ args ++ [path])

    path
  end
end
