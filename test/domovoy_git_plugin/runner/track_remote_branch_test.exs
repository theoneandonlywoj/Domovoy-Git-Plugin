defmodule DomovoyGitPlugin.Runner.TrackRemoteBranchTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.TrackRemoteBranch
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  describe "run/2" do
    test "tracks a remote branch and returns a snapshot" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      Repository.git!(["-C", repository.root, "checkout", "-qb", "feature"])
      Repository.git!(["-C", repository.root, "push", "-u", "origin", "feature"])
      Repository.git!(["-C", repository.root, "checkout", "-q", "main"])
      Repository.git!(["-C", repository.root, "branch", "-D", "feature"])

      assert %Value{value: state, type: RepoStateType} =
               NodeRunner.run(build_node(repository.root, "feature"), [])

      assert state.current_branch == "feature"
      assert state.upstream_branch == "origin/feature"
    end

    test "gives remote_branch_not_found when the remote branch is missing" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert %Error{} = error = NodeRunner.run(build_node(repository.root, "missing"), [])
      assert error.type == :remote_branch_not_found
    end
  end

  @spec build_node(directory :: String.t(), branch :: String.t()) :: Node.t()
  defp build_node(directory, branch) do
    Node.new(%{
      name: "track_remote_branch",
      runner: TrackRemoteBranch,
      type: RepoStateType,
      args: %{
        working_directory: {directory, DirectoryType},
        branch_name: {branch, StringType}
      }
    })
  end
end
