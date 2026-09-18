defmodule DomovoyGitPlugin.Runner.CheckoutOursTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Node
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.CheckoutOurs
  alias DomovoyGitPlugin.Runner.CheckoutTheirs
  alias DomovoyGitPlugin.Runner.Merge
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.Paths, as: PathsType
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  describe "run/2" do
    test "checks out ours without staging" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      start_conflict(repository.root)

      assert %Value{value: state, type: RepoStateType} =
               NodeRunner.run(ours_node(repository.root), [])

      assert state.operation == :merging
      assert state.conflicts != []
      assert File.read!(Path.join(repository.root, "README.md")) == "main-side\n"
    end

    test "checks out theirs without staging" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      start_conflict(repository.root)

      assert %Value{value: state} = NodeRunner.run(theirs_node(repository.root), [])
      assert state.operation == :merging
      assert state.conflicts != []
      assert File.read!(Path.join(repository.root, "README.md")) == "feature-side\n"
    end
  end

  @spec start_conflict(String.t()) :: :ok
  defp start_conflict(root) do
    Repository.git!(["-C", root, "checkout", "-qb", "feature"])
    File.write!(Path.join(root, "README.md"), "feature-side\n")
    Repository.git!(["-C", root, "add", "README.md"])
    Repository.git!(["-C", root, "commit", "-qm", "feature"])
    Repository.git!(["-C", root, "checkout", "-q", "main"])
    File.write!(Path.join(root, "README.md"), "main-side\n")
    Repository.git!(["-C", root, "add", "README.md"])
    Repository.git!(["-C", root, "commit", "-qm", "main"])

    assert %Value{value: %{operation: :merging}} =
             NodeRunner.run(
               Node.new(%{
                 name: "merge",
                 runner: Merge,
                 type: RepoStateType,
                 args: %{
                   working_directory: {root, DirectoryType},
                   ref: {"feature", StringType},
                   fail_on_conflict?: {false, BooleanType}
                 }
               }),
               []
             )

    :ok
  end

  @spec ours_node(directory :: String.t()) :: Node.t()
  defp ours_node(directory) do
    Node.new(%{
      name: "checkout_ours",
      runner: CheckoutOurs,
      type: RepoStateType,
      args: %{
        working_directory: {directory, DirectoryType},
        paths: {["README.md"], PathsType}
      }
    })
  end

  @spec theirs_node(directory :: String.t()) :: Node.t()
  defp theirs_node(directory) do
    Node.new(%{
      name: "checkout_theirs",
      runner: CheckoutTheirs,
      type: RepoStateType,
      args: %{
        working_directory: {directory, DirectoryType},
        paths: {["README.md"], PathsType}
      }
    })
  end
end
