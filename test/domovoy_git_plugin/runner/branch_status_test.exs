defmodule DomovoyGitPlugin.Runner.BranchStatusTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.BranchStatus
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.BranchStatus, as: BranchStatusType

  describe "run/2" do
    test "reports the branch, its upstream, and a clean status" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert %Value{value: status, type: BranchStatusType} =
               NodeRunner.run(build_node(repository.root), [])

      assert status.current_branch == "main"
      assert status.upstream_branch == "origin/main"
      assert status.status == []
    end

    test "reports a nil upstream for a branch that has none" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert %Value{value: status} = NodeRunner.run(build_node(repository.root), [])
      assert status.current_branch == "main"
      assert status.upstream_branch == nil
    end

    test "reports a nil upstream on a newly created branch that was never pushed" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      Repository.git!(["-C", repository.root, "checkout", "-q", "-b", "feature/new"])

      assert %Value{value: status} = NodeRunner.run(build_node(repository.root), [])
      assert status.current_branch == "feature/new"
      assert status.upstream_branch == nil
    end

    test "carries the working tree status entries" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      File.write!(Path.join(repository.root, "README.md"), "changed\n")

      assert %Value{value: status} = NodeRunner.run(build_node(repository.root), [])

      assert status.status == [
               %{path: "README.md", code: " M", index: :unmodified, worktree: :modified}
             ]
    end

    test "returns a contextual error when the directory is not a repository" do
      outside =
        Path.join(System.tmp_dir!(), "domovoy-plain-#{System.unique_integer([:positive])}")

      File.mkdir_p!(outside)
      on_exit(fn -> File.rm_rf(outside) end)

      assert %Error{} = error = NodeRunner.run(build_node(outside), [])
      assert error.type == :git_command_failed
      assert error.metadata[:field_name] == :working_directory
    end
  end

  @spec build_node(directory :: String.t()) :: Node.t()
  defp build_node(directory) do
    Node.new(%{
      name: "branch_status",
      runner: BranchStatus,
      type: BranchStatusType,
      args: %{working_directory: {directory, DirectoryType}}
    })
  end
end
