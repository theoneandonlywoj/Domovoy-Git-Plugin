defmodule DomovoyGitPlugin.Runner.WorktreeResolveTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Capabilities.WorktreeMetadata
  alias DomovoyGitPlugin.Runner.WorktreeResolve
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.Worktree, as: WorktreeType

  setup do
    repository = Repository.create!(remote?: false)
    on_exit(fn -> File.rm_rf(repository.parent) end)

    {:ok, repository: repository}
  end

  describe "run/2" do
    test "describes a worktree that is on the disk", %{repository: repository} do
      path = add_worktree!(repository, "feature")

      :ok =
        WorktreeMetadata.write_record(Path.join(repository.root, ".git"), "feature", %{
          path: path,
          branch: "feature",
          base_branch: "main"
        })

      assert %Value{value: worktree, type: WorktreeType} =
               NodeRunner.run(build_node(repository, "feature"), [])

      assert worktree.repo_root == repository.root
      assert worktree.name == "feature"
      assert worktree.path == path
      assert worktree.exists? == true
      assert worktree.created? == false
      assert worktree.branch == "feature"
      assert worktree.base_branch == "main"
    end

    test "gives exists? false for a name no worktree uses", %{repository: repository} do
      assert %Value{value: worktree} = NodeRunner.run(build_node(repository, "absent"), [])
      assert worktree.exists? == false
      assert worktree.branch == nil
      assert worktree.base_branch == nil
      assert worktree.path == WorktreeMetadata.worktree_path(repository.root, "absent")
    end

    test "takes the name from a bound node", %{repository: repository} do
      add_worktree!(repository, "feature")

      node =
        Node.new(%{
          name: "worktree_resolve",
          runner: WorktreeResolve,
          type: WorktreeType,
          args: %{working_directory: {repository.root, DirectoryType}},
          bind: %{worktree_name: {"computed", StringType}}
        })

      computed = Value.cast!("feature", StringType)

      assert %Value{value: %{name: "feature", exists?: true}} =
               NodeRunner.run(node, [{"computed", computed}])
    end

    test "refuses an unsafe name before the runner runs", %{repository: repository} do
      assert %Error{} = error = NodeRunner.run(build_node(repository, "../escape"), [])
      assert error.type == :invalid_input
      assert [worktree_name: _unsafe] = error.reason
    end

    test "returns a contextual error when the directory is not a repository" do
      outside =
        Path.join(System.tmp_dir!(), "domovoy-plain-#{System.unique_integer([:positive])}")

      File.mkdir_p!(outside)
      on_exit(fn -> File.rm_rf(outside) end)

      assert %Error{} = error = NodeRunner.run(build_node(%{root: outside}, "feature"), [])
      assert error.type == :git_command_failed
    end
  end

  @spec build_node(repository :: %{root: String.t()}, worktree_name :: String.t()) :: Node.t()
  defp build_node(repository, worktree_name) do
    Node.new(%{
      name: "worktree_resolve",
      runner: WorktreeResolve,
      type: WorktreeType,
      args: %{
        working_directory: {repository.root, DirectoryType},
        worktree_name: {worktree_name, StringType}
      }
    })
  end

  @spec add_worktree!(Repository.t(), String.t()) :: String.t()
  defp add_worktree!(repository, name) do
    path = WorktreeMetadata.worktree_path(repository.root, name)
    Repository.git!(["-C", repository.root, "worktree", "add", "-q", "-b", name, path])

    path
  end
end
