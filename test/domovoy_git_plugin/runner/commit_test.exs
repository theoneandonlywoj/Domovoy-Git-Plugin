defmodule DomovoyGitPlugin.Runner.CommitTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Capabilities
  alias DomovoyGitPlugin.Runner.Commit
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  describe "run/2" do
    test "commits staged changes and returns an idle snapshot" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      File.write!(Path.join(repository.root, "README.md"), "changed\n")
      Repository.git!(["-C", repository.root, "add", "README.md"])

      assert %Value{value: state, type: RepoStateType} =
               NodeRunner.run(build_node(repository.root, "Add the snapshot", false), [])

      assert state.operation == :idle
      assert state.conflicts == []
      assert state.dirty? == false
    end

    test "fails when there is nothing to commit and allow_empty? is false" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert %Error{} = error = NodeRunner.run(build_node(repository.root, "Empty", false), [])
      assert error.type == :git_command_failed
    end

    test "creates an empty commit when allow_empty? is true" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert %Value{value: state} =
               NodeRunner.run(build_node(repository.root, "Empty", true), [])

      assert state.operation == :idle
      assert state.dirty? == false
    end

    test "a successful commit on a merging repo shows idle and no conflicts" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      diverge(repository.root)
      File.write!(Path.join(repository.root, "README.md"), "resolved\n")
      assert :ok = Capabilities.add(["README.md"], repository.root, "commit", :paths)

      assert %Value{value: state} =
               NodeRunner.run(build_node(repository.root, "Resolve", false), [])

      assert state.operation == :idle
      assert state.conflicts == []
    end
  end

  @spec build_node(directory :: String.t(), message :: String.t(), allow_empty? :: boolean()) ::
          Node.t()
  defp build_node(directory, message, allow_empty?) do
    Node.new(%{
      name: "commit",
      runner: Commit,
      type: RepoStateType,
      args: %{
        working_directory: {directory, DirectoryType},
        message: {message, StringType},
        allow_empty?: {allow_empty?, BooleanType}
      }
    })
  end

  @spec diverge(String.t()) :: :ok
  defp diverge(root) do
    Repository.git!(["-C", root, "checkout", "-qb", "feature"])
    File.write!(Path.join(root, "README.md"), "feature-side\n")
    Repository.git!(["-C", root, "add", "README.md"])
    Repository.git!(["-C", root, "commit", "-qm", "feature"])
    Repository.git!(["-C", root, "checkout", "-q", "main"])
    File.write!(Path.join(root, "README.md"), "main-side\n")
    Repository.git!(["-C", root, "add", "README.md"])
    Repository.git!(["-C", root, "commit", "-qm", "main"])
    System.cmd("git", ["-C", root, "merge", "--no-edit", "feature"], stderr_to_stdout: true)
    :ok
  end
end
