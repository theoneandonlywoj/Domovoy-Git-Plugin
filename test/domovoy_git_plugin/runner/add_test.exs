defmodule DomovoyGitPlugin.Runner.AddTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.Add
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.Paths, as: PathsType
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  describe "run/2" do
    test "stages the given paths and returns a snapshot" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      File.write!(Path.join(repository.root, "README.md"), "staged\n")

      assert %Value{value: state, type: RepoStateType} =
               NodeRunner.run(build_node(repository.root, ["README.md"]), [])

      assert state.dirty? == true

      assert Enum.any?(state.status, fn entry ->
               entry.path == "README.md" and entry.index == :modified
             end)
    end

    test "does not stage paths that were not named" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      File.write!(Path.join(repository.root, "README.md"), "staged\n")
      File.write!(Path.join(repository.root, "notes.txt"), "left\n")

      assert %Value{value: state} =
               NodeRunner.run(build_node(repository.root, ["README.md"]), [])

      assert Enum.any?(state.status, fn entry -> entry.path == "notes.txt" end)

      notes = Enum.find(state.status, &(&1.path == "notes.txt"))
      assert notes.index == :untracked
    end
  end

  @spec build_node(directory :: String.t(), paths :: [String.t()]) :: Node.t()
  defp build_node(directory, paths) do
    Node.new(%{
      name: "add",
      runner: Add,
      type: RepoStateType,
      args: %{
        working_directory: {directory, DirectoryType},
        paths: {paths, PathsType}
      }
    })
  end
end
