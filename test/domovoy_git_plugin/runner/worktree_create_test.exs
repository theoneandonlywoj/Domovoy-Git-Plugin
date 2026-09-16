defmodule DomovoyGitPlugin.Runner.WorktreeCreateTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Capabilities.WorktreeMetadata
  alias DomovoyGitPlugin.Runner.WorktreeCreate
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.Worktree, as: WorktreeType

  setup do
    repository = Repository.create!(remote?: false)
    on_exit(fn -> File.rm_rf(repository.parent) end)

    {:ok, repository: repository}
  end

  describe "run/2" do
    test "creates the worktree on a new branch cut from the base ref", %{
      repository: repository
    } do
      assert %Value{value: worktree, type: WorktreeType} =
               NodeRunner.run(build_node(repository, %{}), [])

      assert worktree.name == "feature"
      assert worktree.path == WorktreeMetadata.worktree_path(repository.root, "feature")
      assert worktree.branch == "feature-branch"
      assert worktree.base_branch == "main"
      assert worktree.exists? == true
      assert worktree.created? == true

      assert File.dir?(worktree.path)
      assert current_branch(worktree.path) == "feature-branch"
    end

    test "records the base branch so a later diff can find it", %{repository: repository} do
      assert %Value{} = NodeRunner.run(build_node(repository, %{}), [])

      assert WorktreeMetadata.read_base_branch(Path.join(repository.root, ".git"), "feature") ==
               "main"
    end

    test "cuts the branch from the named base ref, not from HEAD", %{repository: repository} do
      Repository.git!(["-C", repository.root, "checkout", "-q", "-b", "other"])
      File.write!(Path.join(repository.root, "other.txt"), "other\n")
      Repository.git!(["-C", repository.root, "add", "other.txt"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "other work"])

      assert %Value{value: worktree} = NodeRunner.run(build_node(repository, %{}), [])

      refute File.exists?(Path.join(worktree.path, "other.txt"))
    end

    test "places the worktree under the main checkout even when run from inside one", %{
      repository: repository
    } do
      assert %Value{value: first} = NodeRunner.run(build_node(repository, %{}), [])

      node =
        build_node(%{root: first.path}, %{
          worktree_name: "second",
          branch_name: "second-branch"
        })

      assert %Value{value: second} = NodeRunner.run(node, [])
      assert second.path == WorktreeMetadata.worktree_path(repository.root, "second")
      refute String.starts_with?(second.path, first.path)
    end

    test "takes its arguments from bound nodes", %{repository: repository} do
      node =
        Node.new(%{
          name: "worktree_create",
          runner: WorktreeCreate,
          type: WorktreeType,
          args: %{
            working_directory: {repository.root, DirectoryType},
            base_branch: {"main", StringType}
          },
          bind: %{worktree_name: {"name", StringType}, branch_name: {"branch", StringType}}
        })

      name = Value.cast!("wired", StringType)
      branch = Value.cast!("wired-branch", StringType)

      assert %Value{value: worktree} = NodeRunner.run(node, [{"name", name}, {"branch", branch}])
      assert worktree.name == "wired"
      assert worktree.branch == "wired-branch"
    end

    test "the validator of the runner refuses a name that escapes the worktrees directory", %{
      repository: repository
    } do
      node = build_node(repository, %{worktree_name: "../escape"})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :invalid_input
      assert [worktree_name: {"is not a safe path segment", _keys}] = error.reason
      refute File.exists?(Path.join(repository.parent, "escape"))
    end

    test "the validator of the runner refuses a path separator or a parent reference", %{
      repository: repository
    } do
      for unsafe <- ["a/b", "..", "."] do
        node = build_node(repository, %{worktree_name: unsafe})

        assert %Error{} = error = NodeRunner.run(node, [])
        assert error.type == :invalid_input
        assert [worktree_name: _unsafe] = error.reason
      end
    end

    test "the input schema refuses an empty worktree name", %{repository: repository} do
      node = build_node(repository, %{worktree_name: ""})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :invalid_input
      assert [worktree_name: {"can't be blank", _keys}] = error.reason
    end

    test "refuses to create a worktree where one already exists", %{repository: repository} do
      assert %Value{} = NodeRunner.run(build_node(repository, %{}), [])

      assert %Error{} = error = NodeRunner.run(build_node(repository, %{}), [])
      assert error.type == :worktree_already_exists
      assert error.metadata[:worktree_name] == "feature"
      assert error.metadata[:node_name] == "worktree_create"
      assert error.metadata[:field_name] == :worktree_name
    end

    test "reports an unknown base ref as a Git command failure", %{repository: repository} do
      node = build_node(repository, %{base_branch: "does-not-exist"})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :git_command_failed
    end

    test "refuses a node that supplies no branch name", %{repository: repository} do
      assert_raise ArgumentError, ~r/required_input.*branch_name/, fn ->
        Node.new(%{
          name: "worktree_create",
          runner: WorktreeCreate,
          type: WorktreeType,
          args: %{
            working_directory: {repository.root, DirectoryType},
            worktree_name: {"feature", StringType},
            base_branch: {"main", StringType}
          }
        })
      end
    end
  end

  @spec build_node(repository :: %{root: String.t()}, overrides :: map()) :: Node.t()
  defp build_node(repository, overrides) do
    literals =
      Map.merge(
        %{worktree_name: "feature", branch_name: "feature-branch", base_branch: "main"},
        overrides
      )

    args =
      literals
      |> Map.new(fn {field, value} -> {field, {value, StringType}} end)
      |> Map.put(:working_directory, {repository.root, DirectoryType})

    Node.new(%{name: "worktree_create", runner: WorktreeCreate, type: WorktreeType, args: args})
  end

  @spec current_branch(String.t()) :: String.t()
  defp current_branch(path),
    do: ["-C", path, "branch", "--show-current"] |> Repository.git!() |> String.trim()
end
