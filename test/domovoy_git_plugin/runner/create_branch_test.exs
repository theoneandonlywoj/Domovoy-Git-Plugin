defmodule DomovoyGitPlugin.Runner.CreateBranchTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.CreateBranch
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  describe "run/2" do
    test "creates a branch from HEAD and returns a snapshot" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert %Value{value: state, type: RepoStateType} =
               NodeRunner.run(build_node(repository.root, "feature", nil), [])

      assert state.current_branch == "feature"
      assert state.upstream_branch == nil
    end

    test "creates a branch from a start point" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      Repository.git!(["-C", repository.root, "branch", "base"])

      assert %Value{value: state} =
               NodeRunner.run(build_node(repository.root, "feature", "base"), [])

      assert state.current_branch == "feature"
    end

    test "fails when the branch already exists" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert %Error{} = error = NodeRunner.run(build_node(repository.root, "main", nil), [])
      assert error.type == :git_command_failed
    end
  end

  @spec build_node(directory :: String.t(), branch :: String.t(), start_point :: String.t() | nil) ::
          Node.t()
  defp build_node(directory, branch, nil) do
    Node.new(%{
      name: "create_branch",
      runner: CreateBranch,
      type: RepoStateType,
      args: %{
        working_directory: {directory, DirectoryType},
        branch_name: {branch, StringType}
      }
    })
  end

  defp build_node(directory, branch, start_point) do
    Node.new(%{
      name: "create_branch",
      runner: CreateBranch,
      type: RepoStateType,
      args: %{
        working_directory: {directory, DirectoryType},
        branch_name: {branch, StringType},
        start_point: {start_point, StringType}
      }
    })
  end
end
