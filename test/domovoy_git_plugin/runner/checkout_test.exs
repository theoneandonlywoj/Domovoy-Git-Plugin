defmodule DomovoyGitPlugin.Runner.CheckoutTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.Checkout
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  describe "run/2" do
    test "checks out an existing local branch and returns a snapshot" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      Repository.git!(["-C", repository.root, "branch", "feature"])

      assert %Value{value: state, type: RepoStateType} =
               NodeRunner.run(build_node(repository.root, "feature"), [])

      assert state.current_branch == "feature"
      assert state.operation == :idle
    end

    test "gives branch_not_found and does not create a missing branch" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert %Error{} = error = NodeRunner.run(build_node(repository.root, "missing"), [])
      assert error.type == :branch_not_found
      refute File.exists?(Path.join(repository.root, ".git/refs/heads/missing"))
    end

    test "fails with git_command_failed when the working tree is dirty" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      Repository.git!(["-C", repository.root, "checkout", "-qb", "feature"])
      File.write!(Path.join(repository.root, "README.md"), "feature\n")
      Repository.git!(["-C", repository.root, "add", "README.md"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "feature"])
      Repository.git!(["-C", repository.root, "checkout", "-q", "main"])
      File.write!(Path.join(repository.root, "README.md"), "dirty\n")

      assert %Error{} = error = NodeRunner.run(build_node(repository.root, "feature"), [])
      assert error.type == :git_command_failed
    end
  end

  @spec build_node(directory :: String.t(), branch :: String.t()) :: Node.t()
  defp build_node(directory, branch) do
    Node.new(%{
      name: "checkout",
      runner: Checkout,
      type: RepoStateType,
      args: %{
        working_directory: {directory, DirectoryType},
        branch_name: {branch, StringType}
      }
    })
  end
end
