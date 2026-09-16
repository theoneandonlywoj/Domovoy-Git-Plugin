defmodule DomovoyGitPlugin.CapabilitiesTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyGitPlugin.Capabilities
  alias DomovoyGitPlugin.Test.Repository

  @node_name "git_capability"
  @field_name :working_directory

  test "resolves a repository root and lists its registered worktrees" do
    repository = Repository.create!(remote?: false, subdirectories: ["lib"])
    on_exit(fn -> File.rm_rf(repository.parent) end)

    lib = Path.join(repository.root, "lib")
    repository_root = repository.root

    assert {:ok, ^repository_root} = Capabilities.repository_root(lib, @node_name, @field_name)

    assert {:ok, worktree_output} =
             Capabilities.worktree_list(repository.root, @node_name, @field_name)

    assert String.contains?(worktree_output, "worktree #{repository.root}")
    assert String.contains?(worktree_output, "branch refs/heads/main")
  end

  test "returns the current branch" do
    repository = Repository.create!(remote?: false)
    on_exit(fn -> File.rm_rf(repository.parent) end)

    assert {:ok, "main"} = Capabilities.current_branch(repository.root, @node_name, @field_name)
  end

  test "returns an error when HEAD is detached" do
    repository = Repository.create!(remote?: false)
    on_exit(fn -> File.rm_rf(repository.parent) end)
    Repository.git!(["-C", repository.root, "checkout", "--detach"])

    assert {:error, %Error{type: :current_branch_not_found} = error} =
             Capabilities.current_branch(repository.root, @node_name, @field_name)

    assert error.metadata == %{node_name: @node_name, field_name: @field_name}
  end

  test "returns command context when repository root discovery fails" do
    directory =
      Path.join(
        System.tmp_dir!(),
        "domovoy-not-a-repository-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)

    assert {:error,
            %Error{
              type: :git_command_failed,
              metadata: %{
                command: ["git", "rev-parse", "--show-toplevel"],
                node_name: @node_name,
                field_name: @field_name
              }
            }} = Capabilities.repository_root(directory, @node_name, @field_name)
  end

  describe "worktree_changes/3" do
    setup do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      path = Path.join([repository.root, ".worktrees", "feature"])
      Repository.git!(["-C", repository.root, "worktree", "add", "-q", "-b", "feature", path])

      worktree = %{
        repo_root: repository.root,
        name: "feature",
        path: path,
        exists?: true,
        created?: false,
        branch: "feature",
        base_branch: "main"
      }

      {:ok, repository: repository, worktree: worktree}
    end

    test "joins the identity of the worktree with its files", %{worktree: worktree} do
      File.write!(Path.join(worktree.path, "README.md"), "changed\n")

      assert {:ok, diff} = Capabilities.worktree_changes(worktree, nil, @node_name)
      assert diff.worktree_name == "feature"
      assert diff.path == worktree.path
      assert diff.branch == "feature"
      assert diff.base_branch == "main"
      assert [%{file: "README.md"}] = diff.files
    end

    test "a base_branch argument overrides the recorded one", %{worktree: worktree} do
      assert {:ok, %{base_branch: "feature"}} =
               Capabilities.worktree_changes(worktree, "feature", @node_name)
    end

    test "reports a worktree with no base branch at all", %{worktree: worktree} do
      worktree = %{worktree | base_branch: nil}

      assert {:error, %Error{} = error} = Capabilities.worktree_changes(worktree, nil, @node_name)
      assert error.type == :git_worktree_diff_failed
      assert error.reason =~ "no recorded base branch"
      assert error.metadata == %{node_name: @node_name, field_name: :base_branch}
    end
  end

  test "rejects unsafe worktree names" do
    assert Capabilities.valid_worktree_name?("feature")
    refute Capabilities.valid_worktree_name?("../escape")
    refute Capabilities.valid_worktree_name?(".")
    refute Capabilities.valid_worktree_name?("")
  end

  test "extracts expanded paths from worktree porcelain output" do
    assert Capabilities.worktree_paths("worktree /repo\nHEAD abc\nworktree relative\n") == [
             "/repo",
             Path.expand("relative")
           ]
  end
end
