defmodule DomovoyGitPlugin.Runner.AddAllTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.AddAll
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  describe "run/2" do
    test "stages every change including untracked files" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      File.write!(Path.join(repository.root, "README.md"), "changed\n")
      File.write!(Path.join(repository.root, "notes.txt"), "new\n")

      assert %Value{value: state, type: RepoStateType} =
               NodeRunner.run(build_node(repository.root), [])

      paths = Enum.map(state.status, & &1.path)
      assert "README.md" in paths
      assert "notes.txt" in paths
      assert Enum.all?(state.status, &(&1.worktree == :unmodified))
    end
  end

  @spec build_node(directory :: String.t()) :: Node.t()
  defp build_node(directory) do
    Node.new(%{
      name: "add_all",
      runner: AddAll,
      type: RepoStateType,
      args: %{working_directory: {directory, DirectoryType}}
    })
  end
end
