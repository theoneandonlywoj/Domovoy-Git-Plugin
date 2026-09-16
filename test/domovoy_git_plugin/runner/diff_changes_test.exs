defmodule DomovoyGitPlugin.Runner.DiffChangesTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.DiffChanges
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
      assert %Value{value: [], type: DiffType} = NodeRunner.run(build_node(repository.root), [])
    end

    test "includes tracked changes and untracked files together", %{repository: repository} do
      File.write!(Path.join(repository.root, "README.md"), "changed\n")
      File.write!(Path.join(repository.root, "untracked.txt"), "brand new\n")

      assert %Value{value: file_diffs} = NodeRunner.run(build_node(repository.root), [])

      by_file = Map.new(file_diffs, fn file_diff -> {file_diff.file, file_diff} end)
      assert Map.has_key?(by_file, "README.md")
      assert Map.has_key?(by_file, "untracked.txt")
    end

    test "lists tracked entries before untracked ones", %{repository: repository} do
      File.write!(Path.join(repository.root, "README.md"), "changed\n")
      File.write!(Path.join(repository.root, "untracked.txt"), "brand new\n")

      assert %Value{value: file_diffs} = NodeRunner.run(build_node(repository.root), [])

      assert Enum.map(file_diffs, fn file_diff -> file_diff.file end) ==
               ["README.md", "untracked.txt"]
    end

    test "reports an untracked file inside a new directory", %{repository: repository} do
      nested = Path.join(repository.root, "lib/deep")
      File.mkdir_p!(nested)
      File.write!(Path.join(nested, "example.ex"), "defmodule Example do\nend\n")

      assert %Value{value: [file_diff]} = NodeRunner.run(build_node(repository.root), [])
      assert file_diff.file == "lib/deep/example.ex"
    end

    test "returns a contextual error when the directory is not a repository" do
      outside =
        Path.join(System.tmp_dir!(), "domovoy-plain-#{System.unique_integer([:positive])}")

      File.mkdir_p!(outside)
      on_exit(fn -> File.rm_rf(outside) end)

      assert %Error{} = error = NodeRunner.run(build_node(outside), [])
      assert error.type == :git_command_failed
    end
  end

  @spec build_node(directory :: String.t()) :: Node.t()
  defp build_node(directory) do
    Node.new(%{
      name: "diff_changes",
      runner: DiffChanges,
      type: DiffType,
      args: %{working_directory: {directory, DirectoryType}}
    })
  end
end
