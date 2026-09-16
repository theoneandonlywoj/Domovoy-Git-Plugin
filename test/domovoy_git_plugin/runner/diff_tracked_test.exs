defmodule DomovoyGitPlugin.Runner.DiffTrackedTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.DiffTracked
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.Diff, as: DiffType

  setup do
    repository = Repository.create!(remote?: false)
    on_exit(fn -> File.rm_rf(repository.parent) end)

    {:ok, repository: repository}
  end

  describe "run/2" do
    test "returns an empty diff for a clean tree", %{repository: repository} do
      assert %Value{value: [], type: DiffType} = NodeRunner.run(literal_node(repository.root), [])
    end

    test "returns the parsed diff of an unstaged change", %{repository: repository} do
      File.write!(Path.join(repository.root, "README.md"), "changed\n")

      assert %Value{value: [file_diff]} = NodeRunner.run(literal_node(repository.root), [])
      assert file_diff.file == "README.md"
      assert [hunk] = file_diff.hunks
      assert hunk.added_lines == ["changed"]
      assert hunk.removed_lines == ["test"]
    end

    test "includes staged changes, since the diff is taken against HEAD", %{
      repository: repository
    } do
      File.write!(Path.join(repository.root, "staged.txt"), "staged\n")
      Repository.git!(["-C", repository.root, "add", "staged.txt"])

      assert %Value{value: [file_diff]} = NodeRunner.run(literal_node(repository.root), [])
      assert file_diff.file == "staged.txt"
      assert [%{added_lines: ["staged"]}] = file_diff.hunks
    end

    test "excludes untracked files, which Git cannot diff", %{repository: repository} do
      File.write!(Path.join(repository.root, "untracked.txt"), "new\n")

      assert %Value{value: []} = NodeRunner.run(literal_node(repository.root), [])
    end

    test "diffs a directory that a bound node gives", %{repository: repository} do
      File.write!(Path.join(repository.root, "README.md"), "changed\n")

      node =
        Node.new(%{
          name: "diff_tracked",
          runner: DiffTracked,
          type: DiffType,
          bind: %{working_directory: {"checkout", DirectoryType}}
        })

      checkout = Value.cast!(repository.root, DirectoryType)

      assert %Value{value: [%{file: "README.md"}]} =
               NodeRunner.run(node, [{"checkout", checkout}])
    end

    test "returns a contextual error when the directory is not a repository" do
      outside =
        Path.join(System.tmp_dir!(), "domovoy-plain-#{System.unique_integer([:positive])}")

      File.mkdir_p!(outside)
      on_exit(fn -> File.rm_rf(outside) end)

      assert %Error{} = error = NodeRunner.run(literal_node(outside), [])
      assert error.type == :git_command_failed
      assert error.metadata[:command] == ["git", "diff", "HEAD"]
    end
  end

  @spec literal_node(directory :: String.t()) :: Node.t()
  defp literal_node(directory) do
    Node.new(%{
      name: "diff_tracked",
      runner: DiffTracked,
      type: DiffType,
      args: %{working_directory: {directory, DirectoryType}}
    })
  end
end
