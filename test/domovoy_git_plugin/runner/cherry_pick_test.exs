defmodule DomovoyGitPlugin.Runner.CherryPickTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Capabilities
  alias DomovoyGitPlugin.Runner.CherryPick
  alias DomovoyGitPlugin.Runner.CherryPickAbort
  alias DomovoyGitPlugin.Runner.CherryPickContinue
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  describe "run/2" do
    test "cherry-picks a commit without conflicts" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      Repository.git!(["-C", repository.root, "checkout", "-qb", "feature"])
      File.write!(Path.join(repository.root, "feature.txt"), "ok\n")
      Repository.git!(["-C", repository.root, "add", "feature.txt"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "feature"])
      sha = repository.root |> cherry_sha() |> String.trim()
      Repository.git!(["-C", repository.root, "checkout", "-q", "main"])

      assert %Value{value: state, type: RepoStateType} =
               NodeRunner.run(pick_node(repository.root, sha, true), [])

      assert state.operation == :idle
      assert File.exists?(Path.join(repository.root, "feature.txt"))
    end

    test "returns a cherry-picking snapshot when fail_on_conflict? is false" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      sha = diverge_for_pick(repository.root)

      assert %Value{value: state} = NodeRunner.run(pick_node(repository.root, sha, false), [])
      assert state.operation == :cherry_picking
      assert state.conflicts != []
    end

    test "fails on conflict when fail_on_conflict? is true" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      sha = diverge_for_pick(repository.root)

      assert %Error{} = error = NodeRunner.run(pick_node(repository.root, sha, true), [])
      assert error.type == :git_command_failed
    end

    test "abort returns an idle snapshot" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      sha = diverge_for_pick(repository.root)

      assert %Value{value: %{operation: :cherry_picking}} =
               NodeRunner.run(pick_node(repository.root, sha, false), [])

      assert %Value{value: state} =
               NodeRunner.run(
                 Node.new(%{
                   name: "cherry_pick_abort",
                   runner: CherryPickAbort,
                   type: RepoStateType,
                   args: %{working_directory: {repository.root, DirectoryType}}
                 }),
                 []
               )

      assert state.operation == :idle
    end

    test "continue after add finishes the cherry-pick" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      sha = diverge_for_pick(repository.root)
      assert %Value{} = NodeRunner.run(pick_node(repository.root, sha, false), [])
      File.write!(Path.join(repository.root, "README.md"), "resolved\n")
      assert :ok = Capabilities.add(["README.md"], repository.root, "cherry_pick", :paths)

      assert %Value{value: state} =
               NodeRunner.run(
                 Node.new(%{
                   name: "cherry_pick_continue",
                   runner: CherryPickContinue,
                   type: RepoStateType,
                   args: %{working_directory: {repository.root, DirectoryType}}
                 }),
                 []
               )

      assert state.operation == :idle
      assert state.conflicts == []
    end
  end

  @spec pick_node(directory :: String.t(), ref :: String.t(), fail_on_conflict? :: boolean()) ::
          Node.t()
  defp pick_node(directory, ref, fail_on_conflict?) do
    Node.new(%{
      name: "cherry_pick",
      runner: CherryPick,
      type: RepoStateType,
      args: %{
        working_directory: {directory, DirectoryType},
        ref: {ref, StringType},
        fail_on_conflict?: {fail_on_conflict?, BooleanType}
      }
    })
  end

  @spec diverge_for_pick(String.t()) :: String.t()
  defp diverge_for_pick(root) do
    Repository.git!(["-C", root, "checkout", "-qb", "feature"])
    File.write!(Path.join(root, "README.md"), "feature-side\n")
    Repository.git!(["-C", root, "add", "README.md"])
    Repository.git!(["-C", root, "commit", "-qm", "feature"])
    sha = root |> cherry_sha() |> String.trim()
    Repository.git!(["-C", root, "checkout", "-q", "main"])
    File.write!(Path.join(root, "README.md"), "main-side\n")
    Repository.git!(["-C", root, "add", "README.md"])
    Repository.git!(["-C", root, "commit", "-qm", "main"])
    sha
  end

  @spec cherry_sha(String.t()) :: String.t()
  defp cherry_sha(root), do: Repository.git!(["-C", root, "rev-parse", "HEAD"])
end
