defmodule DomovoyGitPlugin.Runner.MergeTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Capabilities
  alias DomovoyGitPlugin.Runner.Merge
  alias DomovoyGitPlugin.Runner.MergeAbort
  alias DomovoyGitPlugin.Runner.MergeContinue
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  describe "run/2" do
    test "merges a clean branch" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      Repository.git!(["-C", repository.root, "checkout", "-qb", "feature"])
      File.write!(Path.join(repository.root, "feature.txt"), "ok\n")
      Repository.git!(["-C", repository.root, "add", "feature.txt"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "feature"])
      Repository.git!(["-C", repository.root, "checkout", "-q", "main"])

      assert %Value{value: state, type: RepoStateType} =
               NodeRunner.run(merge_node(repository.root, "feature", true), [])

      assert state.operation == :idle
      assert state.conflicts == []
      assert File.exists?(Path.join(repository.root, "feature.txt"))
    end

    test "fails on conflict when fail_on_conflict? is true" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      diverge(repository.root)

      assert %Error{} = error = NodeRunner.run(merge_node(repository.root, "feature", true), [])
      assert error.type == :git_command_failed
    end

    test "returns a merging snapshot when fail_on_conflict? is false" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      diverge(repository.root)

      assert %Value{value: state} =
               NodeRunner.run(merge_node(repository.root, "feature", false), [])

      assert state.operation == :merging
      assert [%{path: "README.md"}] = state.conflicts
    end

    test "still errors on a missing ref when fail_on_conflict? is false" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert %Error{} = error = NodeRunner.run(merge_node(repository.root, "missing", false), [])
      assert error.type == :git_command_failed
    end
  end

  describe "abort and continue" do
    test "abort returns an idle snapshot" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      diverge(repository.root)

      assert %Value{value: %{operation: :merging}} =
               NodeRunner.run(merge_node(repository.root, "feature", false), [])

      assert %Value{value: state} = NodeRunner.run(abort_node(repository.root), [])
      assert state.operation == :idle
      assert state.conflicts == []
    end

    test "continue after add finishes the merge" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      diverge(repository.root)
      assert %Value{} = NodeRunner.run(merge_node(repository.root, "feature", false), [])
      File.write!(Path.join(repository.root, "README.md"), "resolved\n")
      assert :ok = Capabilities.add(["README.md"], repository.root, "merge", :paths)

      assert %Value{value: state} = NodeRunner.run(continue_node(repository.root), [])
      assert state.operation == :idle
      assert state.conflicts == []
    end
  end

  @spec merge_node(directory :: String.t(), ref :: String.t(), fail_on_conflict? :: boolean()) ::
          Node.t()
  defp merge_node(directory, ref, fail_on_conflict?) do
    Node.new(%{
      name: "merge",
      runner: Merge,
      type: RepoStateType,
      args: %{
        working_directory: {directory, DirectoryType},
        ref: {ref, StringType},
        fail_on_conflict?: {fail_on_conflict?, BooleanType}
      }
    })
  end

  @spec abort_node(directory :: String.t()) :: Node.t()
  defp abort_node(directory) do
    Node.new(%{
      name: "merge_abort",
      runner: MergeAbort,
      type: RepoStateType,
      args: %{working_directory: {directory, DirectoryType}}
    })
  end

  @spec continue_node(directory :: String.t()) :: Node.t()
  defp continue_node(directory) do
    Node.new(%{
      name: "merge_continue",
      runner: MergeContinue,
      type: RepoStateType,
      args: %{working_directory: {directory, DirectoryType}}
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
    :ok
  end
end
