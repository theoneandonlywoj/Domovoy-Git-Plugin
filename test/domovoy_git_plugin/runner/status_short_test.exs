defmodule DomovoyGitPlugin.Runner.StatusShortTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.StatusShort
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.StatusEntries, as: StatusEntriesType

  setup do
    repository = Repository.create!(remote?: false)
    on_exit(fn -> File.rm_rf(repository.parent) end)

    {:ok, repository: repository}
  end

  describe "run/2" do
    test "returns an empty list for a clean tree", %{repository: repository} do
      assert %Value{value: [], type: StatusEntriesType} =
               NodeRunner.run(literal_node(repository.root), [])
    end

    test "reports a modified tracked file with its porcelain code", %{repository: repository} do
      File.write!(Path.join(repository.root, "README.md"), "changed\n")

      assert %Value{value: [entry]} = NodeRunner.run(literal_node(repository.root), [])
      assert entry.path == "README.md"
      assert entry.code == " M"
      assert entry.index == :unmodified
      assert entry.worktree == :modified
    end

    test "reports an untracked file and a staged addition", %{repository: repository} do
      File.write!(Path.join(repository.root, "untracked.txt"), "new\n")
      File.write!(Path.join(repository.root, "staged.txt"), "new\n")
      Repository.git!(["-C", repository.root, "add", "staged.txt"])

      assert %Value{value: entries} = NodeRunner.run(literal_node(repository.root), [])

      by_path = Map.new(entries, fn entry -> {entry.path, entry} end)

      assert %{code: "??", index: :untracked, worktree: :untracked} = by_path["untracked.txt"]
      assert %{code: "A ", index: :added, worktree: :unmodified} = by_path["staged.txt"]
    end

    test "inspects a directory that a bound node gives", %{repository: repository} do
      File.write!(Path.join(repository.root, "README.md"), "changed\n")

      node =
        Node.new(%{
          name: "status_short",
          runner: StatusShort,
          type: StatusEntriesType,
          bind: %{working_directory: {"checkout", DirectoryType}}
        })

      checkout = Value.cast!(repository.root, DirectoryType)

      assert %Value{value: [%{path: "README.md"}]} =
               NodeRunner.run(node, [{"checkout", checkout}])
    end

    test "returns a contextual error when the directory is not a repository" do
      outside =
        Path.join(System.tmp_dir!(), "domovoy-plain-#{System.unique_integer([:positive])}")

      File.mkdir_p!(outside)
      on_exit(fn -> File.rm_rf(outside) end)

      assert %Error{} = error = NodeRunner.run(literal_node(outside), [])
      assert error.type == :git_command_failed
      assert error.metadata[:command] == ["git", "status", "--porcelain"]
    end
  end

  @spec literal_node(directory :: String.t()) :: Node.t()
  defp literal_node(directory) do
    Node.new(%{
      name: "status_short",
      runner: StatusShort,
      type: StatusEntriesType,
      args: %{working_directory: {directory, DirectoryType}}
    })
  end
end
