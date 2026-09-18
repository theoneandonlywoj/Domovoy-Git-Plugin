defmodule DomovoyGitPlugin.Runner.RebaseTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Capabilities
  alias DomovoyGitPlugin.Runner.Rebase
  alias DomovoyGitPlugin.Runner.RebaseAbort
  alias DomovoyGitPlugin.Runner.RebaseContinue
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  describe "run/2" do
    test "rebases a branch without conflicts" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      Repository.git!(["-C", repository.root, "checkout", "-qb", "feature"])
      File.write!(Path.join(repository.root, "feature.txt"), "ok\n")
      Repository.git!(["-C", repository.root, "add", "feature.txt"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "feature"])
      Repository.git!(["-C", repository.root, "checkout", "-q", "main"])
      File.write!(Path.join(repository.root, "main.txt"), "ok\n")
      Repository.git!(["-C", repository.root, "add", "main.txt"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "main"])
      Repository.git!(["-C", repository.root, "checkout", "-q", "feature"])

      assert %Value{value: state, type: RepoStateType} =
               NodeRunner.run(rebase_node(repository.root, "main", true), [])

      assert state.operation == :idle
      assert state.conflicts == []
    end

    test "returns a rebasing snapshot when fail_on_conflict? is false" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      diverge_for_rebase(repository.root)

      assert %Value{value: state} =
               NodeRunner.run(rebase_node(repository.root, "main", false), [])

      assert state.operation == :rebasing
      assert state.conflicts != []
    end

    test "fails on conflict when fail_on_conflict? is true" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      diverge_for_rebase(repository.root)

      assert %Error{} = error = NodeRunner.run(rebase_node(repository.root, "main", true), [])
      assert error.type == :git_command_failed
    end

    test "abort returns an idle snapshot" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      diverge_for_rebase(repository.root)

      assert %Value{value: %{operation: :rebasing}} =
               NodeRunner.run(rebase_node(repository.root, "main", false), [])

      assert %Value{value: state} =
               NodeRunner.run(
                 Node.new(%{
                   name: "rebase_abort",
                   runner: RebaseAbort,
                   type: RepoStateType,
                   args: %{working_directory: {repository.root, DirectoryType}}
                 }),
                 []
               )

      assert state.operation == :idle
    end

    test "continue after add finishes the rebase" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      diverge_for_rebase(repository.root)
      assert %Value{} = NodeRunner.run(rebase_node(repository.root, "main", false), [])
      File.write!(Path.join(repository.root, "README.md"), "resolved\n")
      assert :ok = Capabilities.add(["README.md"], repository.root, "rebase", :paths)

      assert %Value{value: state} =
               NodeRunner.run(
                 Node.new(%{
                   name: "rebase_continue",
                   runner: RebaseContinue,
                   type: RepoStateType,
                   args: %{working_directory: {repository.root, DirectoryType}}
                 }),
                 []
               )

      assert state.operation == :idle
      assert state.conflicts == []
    end
  end

  @spec rebase_node(directory :: String.t(), ref :: String.t(), fail_on_conflict? :: boolean()) ::
          Node.t()
  defp rebase_node(directory, ref, fail_on_conflict?) do
    Node.new(%{
      name: "rebase",
      runner: Rebase,
      type: RepoStateType,
      args: %{
        working_directory: {directory, DirectoryType},
        ref: {ref, StringType},
        fail_on_conflict?: {fail_on_conflict?, BooleanType}
      }
    })
  end

  @spec diverge_for_rebase(String.t()) :: :ok
  defp diverge_for_rebase(root) do
    Repository.git!(["-C", root, "checkout", "-qb", "feature"])
    File.write!(Path.join(root, "README.md"), "feature-side\n")
    Repository.git!(["-C", root, "add", "README.md"])
    Repository.git!(["-C", root, "commit", "-qm", "feature"])
    Repository.git!(["-C", root, "checkout", "-q", "main"])
    File.write!(Path.join(root, "README.md"), "main-side\n")
    Repository.git!(["-C", root, "add", "README.md"])
    Repository.git!(["-C", root, "commit", "-qm", "main"])
    Repository.git!(["-C", root, "checkout", "-q", "feature"])
    :ok
  end
end
