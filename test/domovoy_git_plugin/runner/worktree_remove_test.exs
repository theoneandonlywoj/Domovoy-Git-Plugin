defmodule DomovoyGitPlugin.Runner.WorktreeRemoveTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Capabilities.WorktreeMetadata
  alias DomovoyGitPlugin.Runner.WorktreeRemove
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.WorktreeRemovalStatus, as: WorktreeRemovalStatusType

  setup do
    repository = Repository.create!(remote?: false)
    on_exit(fn -> File.rm_rf(repository.parent) end)

    {:ok, repository: repository}
  end

  describe "run/2" do
    test "removes a worktree and leaves its branch alone by default", %{repository: repository} do
      path = add_worktree!(repository, "feature")

      assert %Value{value: removal, type: WorktreeRemovalStatusType} =
               NodeRunner.run(build_node(repository, "feature"), [])

      assert removal.worktree_name == "feature"
      assert removal.path == path
      assert removal.branch == "feature"
      assert removal.removed? == true
      assert removal.branch_deleted? == false

      refute File.dir?(path)
      assert branches(repository) =~ "feature"
    end

    test "deletes the branch when asked", %{repository: repository} do
      add_worktree!(repository, "feature")

      node = build_node(repository, "feature", %{delete_branch?: true})

      assert %Value{value: %{branch_deleted?: true}} = NodeRunner.run(node, [])
      refute branches(repository) =~ "feature"
    end

    test "discards the base-branch record it kept", %{repository: repository} do
      path = add_worktree!(repository, "feature")
      git_common_directory = Path.join(repository.root, ".git")

      :ok =
        WorktreeMetadata.write_record(git_common_directory, "feature", %{
          path: path,
          branch: "feature",
          base_branch: "main"
        })

      assert %Value{} = NodeRunner.run(build_node(repository, "feature"), [])
      assert WorktreeMetadata.read_base_branch(git_common_directory, "feature") == nil
    end

    test "takes the worktree name from a bound node", %{repository: repository} do
      add_worktree!(repository, "feature")

      node =
        Node.new(%{
          name: "worktree_remove",
          runner: WorktreeRemove,
          type: WorktreeRemovalStatusType,
          args: %{working_directory: {repository.root, DirectoryType}},
          bind: %{worktree_name: {"computed", StringType}}
        })

      computed = Value.cast!("feature", StringType)

      assert %Value{value: %{worktree_name: "feature"}} =
               NodeRunner.run(node, [{"computed", computed}])
    end

    test "reports branch_deleted? false for a detached worktree even when asked", %{
      repository: repository
    } do
      Repository.git!([
        "-C",
        repository.root,
        "worktree",
        "add",
        "-q",
        "--detach",
        WorktreeMetadata.worktree_path(repository.root, "detached")
      ])

      node = build_node(repository, "detached", %{delete_branch?: true})

      assert %Value{value: removal} = NodeRunner.run(node, [])
      assert removal.branch == nil
      assert removal.branch_deleted? == false
    end

    test "lets Git refuse a worktree holding uncommitted changes", %{repository: repository} do
      path = add_worktree!(repository, "feature")
      File.write!(Path.join(path, "dirty.txt"), "uncommitted\n")

      assert %Error{} = error = NodeRunner.run(build_node(repository, "feature"), [])
      assert error.type == :git_command_failed
      assert error.metadata[:field_name] == :worktree_name
      assert File.dir?(path)
    end

    test "removes a dirty worktree when forced", %{repository: repository} do
      path = add_worktree!(repository, "feature")
      File.write!(Path.join(path, "dirty.txt"), "uncommitted\n")

      node = build_node(repository, "feature", %{force?: true})

      assert %Value{value: %{removed?: true}} = NodeRunner.run(node, [])
      refute File.dir?(path)
    end

    test "returns a contextual error for a name no worktree matches", %{repository: repository} do
      assert %Error{} = error = NodeRunner.run(build_node(repository, "absent"), [])
      assert error.type == :worktree_not_registered
      assert error.metadata[:worktree_name] == "absent"
      assert error.metadata[:node_name] == "worktree_remove"
    end

    test "refuses an unsafe name before the runner runs", %{repository: repository} do
      assert %Error{} = error = NodeRunner.run(build_node(repository, "../escape"), [])
      assert error.type == :invalid_input
      assert [worktree_name: _unsafe] = error.reason
    end

    test "refuses a node that supplies no worktree name", %{repository: repository} do
      assert_raise ArgumentError, ~r/required_input.*worktree_name/, fn ->
        Node.new(%{
          name: "worktree_remove",
          runner: WorktreeRemove,
          type: WorktreeRemovalStatusType,
          args: %{working_directory: {repository.root, DirectoryType}}
        })
      end
    end
  end

  @spec build_node(repository :: Repository.t(), worktree_name :: String.t(), flags :: map()) ::
          Node.t()
  defp build_node(repository, worktree_name, flags \\ %{}) do
    args =
      flags
      |> Map.new(fn {field, value} -> {field, {value, BooleanType}} end)
      |> Map.merge(%{
        working_directory: {repository.root, DirectoryType},
        worktree_name: {worktree_name, StringType}
      })

    Node.new(%{
      name: "worktree_remove",
      runner: WorktreeRemove,
      type: WorktreeRemovalStatusType,
      args: args
    })
  end

  @spec add_worktree!(Repository.t(), String.t()) :: String.t()
  defp add_worktree!(repository, name) do
    path = WorktreeMetadata.worktree_path(repository.root, name)
    Repository.git!(["-C", repository.root, "worktree", "add", "-q", "-b", name, path])

    path
  end

  @spec branches(Repository.t()) :: String.t()
  defp branches(repository),
    do: Repository.git!(["-C", repository.root, "branch", "--format=%(refname:short)"])
end
