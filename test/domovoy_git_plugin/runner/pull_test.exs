defmodule DomovoyGitPlugin.Runner.PullTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.Pull
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  describe "run/2" do
    test "fetches and merges origin" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      other = clone_and_commit(repository)

      assert %Value{value: state, type: RepoStateType} =
               NodeRunner.run(pull_node(repository.root, false, true), [])

      assert state.operation == :idle
      assert state.behind == 0
      assert File.exists?(Path.join(repository.root, "other.txt"))
      File.rm_rf(other)
    end

    test "fetches and rebases onto origin" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      File.write!(Path.join(repository.root, "local.txt"), "local\n")
      Repository.git!(["-C", repository.root, "add", "local.txt"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "local"])
      other = clone_and_commit(repository)

      assert %Value{value: state} = NodeRunner.run(pull_node(repository.root, true, true), [])
      assert state.operation == :idle
      assert File.exists?(Path.join(repository.root, "other.txt"))
      assert File.exists?(Path.join(repository.root, "local.txt"))
      File.rm_rf(other)
    end

    test "returns a merging snapshot when fail_on_conflict? is false" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      File.write!(Path.join(repository.root, "README.md"), "local\n")
      Repository.git!(["-C", repository.root, "add", "README.md"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "local"])
      other = clone_and_change_readme(repository)

      assert %Value{value: state} = NodeRunner.run(pull_node(repository.root, false, false), [])
      assert state.operation == :merging
      assert state.conflicts != []
      File.rm_rf(other)
    end

    test "fails on conflict when fail_on_conflict? is true" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      File.write!(Path.join(repository.root, "README.md"), "local\n")
      Repository.git!(["-C", repository.root, "add", "README.md"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "local"])
      other = clone_and_change_readme(repository)

      assert %Error{} = error = NodeRunner.run(pull_node(repository.root, false, true), [])
      assert error.type == :git_command_failed
      File.rm_rf(other)
    end
  end

  @spec pull_node(directory :: String.t(), rebase? :: boolean(), fail_on_conflict? :: boolean()) ::
          Node.t()
  defp pull_node(directory, rebase?, fail_on_conflict?) do
    Node.new(%{
      name: "pull",
      runner: Pull,
      type: RepoStateType,
      args: %{
        working_directory: {directory, DirectoryType},
        rebase?: {rebase?, BooleanType},
        fail_on_conflict?: {fail_on_conflict?, BooleanType}
      }
    })
  end

  @spec clone_and_commit(Repository.t()) :: String.t()
  defp clone_and_commit(repository) do
    other = Path.join(repository.parent, "other")
    Repository.git!(["clone", repository.remote, other])
    Repository.git!(["-C", other, "config", "user.email", "test@example.com"])
    Repository.git!(["-C", other, "config", "user.name", "Domovoy Test"])
    File.write!(Path.join(other, "other.txt"), "other\n")
    Repository.git!(["-C", other, "add", "other.txt"])
    Repository.git!(["-C", other, "commit", "-qm", "other"])
    Repository.git!(["-C", other, "push", "origin", "main"])
    other
  end

  @spec clone_and_change_readme(Repository.t()) :: String.t()
  defp clone_and_change_readme(repository) do
    other = Path.join(repository.parent, "other")
    Repository.git!(["clone", repository.remote, other])
    Repository.git!(["-C", other, "config", "user.email", "test@example.com"])
    Repository.git!(["-C", other, "config", "user.name", "Domovoy Test"])
    File.write!(Path.join(other, "README.md"), "remote\n")
    Repository.git!(["-C", other, "add", "README.md"])
    Repository.git!(["-C", other, "commit", "-qm", "remote"])
    Repository.git!(["-C", other, "push", "origin", "main"])
    other
  end
end
