defmodule DomovoyGitPlugin.Runner.InspectRepoTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.InspectRepo
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  describe "run/2" do
    test "returns a snapshot of a clean main checkout" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert %Value{value: state, type: RepoStateType} =
               NodeRunner.run(build_node(repository.root), [])

      assert state.checkout == :main
      assert state.current_branch == "main"
      assert state.upstream_branch == "origin/main"
      assert state.operation == :idle
      assert state.conflicts == []
      assert state.dirty? == false
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
      name: "inspect_repo",
      runner: InspectRepo,
      type: RepoStateType,
      args: %{working_directory: {directory, DirectoryType}}
    })
  end
end
