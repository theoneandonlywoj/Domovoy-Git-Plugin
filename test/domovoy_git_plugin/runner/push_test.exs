defmodule DomovoyGitPlugin.Runner.PushTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.Push
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  describe "run/2" do
    test "pushes the current branch to origin" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      File.write!(Path.join(repository.root, "README.md"), "pushed\n")
      Repository.git!(["-C", repository.root, "add", "README.md"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "pushed"])

      assert %Value{value: state, type: RepoStateType} =
               NodeRunner.run(push_node(repository.root, nil, false), [])

      assert state.ahead == 0
    end

    test "fails when the refspec matches no local ref" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert %Error{} =
               error =
               NodeRunner.run(push_node(repository.root, "no-such-branch", false), [])

      assert error.type == :git_command_failed
    end

    test "sets upstream when set_upstream? is true" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      Repository.git!(["-C", repository.root, "checkout", "-qb", "feature"])

      assert %Value{value: state} = NodeRunner.run(push_node(repository.root, nil, true), [])
      assert state.current_branch == "feature"
      assert state.upstream_branch == "origin/feature"
    end

    test "pushes a named refspec" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      Repository.git!(["-C", repository.root, "checkout", "-qb", "feature"])
      File.write!(Path.join(repository.root, "feature.txt"), "ok\n")
      Repository.git!(["-C", repository.root, "add", "feature.txt"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "feature"])

      assert %Value{value: state} =
               NodeRunner.run(push_node(repository.root, "feature", false), [])

      assert state.current_branch == "feature"
    end
  end

  @spec push_node(
          directory :: String.t(),
          refspec :: String.t() | nil,
          set_upstream? :: boolean()
        ) :: Node.t()
  defp push_node(directory, nil, set_upstream?) do
    Node.new(%{
      name: "push",
      runner: Push,
      type: RepoStateType,
      args: %{
        working_directory: {directory, DirectoryType},
        set_upstream?: {set_upstream?, BooleanType}
      }
    })
  end

  defp push_node(directory, refspec, set_upstream?) do
    Node.new(%{
      name: "push",
      runner: Push,
      type: RepoStateType,
      args: %{
        working_directory: {directory, DirectoryType},
        refspec: {refspec, StringType},
        set_upstream?: {set_upstream?, BooleanType}
      }
    })
  end
end
