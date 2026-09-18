defmodule DomovoyGitPlugin.Capabilities.RepoStateTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyGitPlugin.Capabilities
  alias DomovoyGitPlugin.Capabilities.WorktreeMetadata
  alias DomovoyGitPlugin.Test.Repository

  @node_name "inspect_repo"
  @field_name :working_directory

  describe "repo_state/3" do
    test "describes a clean main checkout" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert {:ok, state} = Capabilities.repo_state(repository.root, @node_name, @field_name)

      assert state.path == repository.root
      assert state.repo_root == repository.root
      assert state.checkout == :main
      assert state.worktree_name == nil
      assert state.base_branch == nil
      assert state.current_branch == "main"
      assert state.detached? == false
      assert state.upstream_branch == "origin/main"
      assert state.ahead == 0
      assert state.behind == 0
      assert state.dirty? == false
      assert state.operation == :idle
      assert state.status == []
      assert state.conflicts == []
    end

    test "describes a linked managed worktree" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      worktree = add_worktree(repository, "feature", managed?: true)

      assert {:ok, state} = Capabilities.repo_state(worktree, @node_name, @field_name)

      assert state.path == worktree
      assert state.repo_root == repository.root
      assert state.checkout == :worktree
      assert state.worktree_name == "feature"
      assert state.base_branch == "main"
      assert state.current_branch == "feature"
    end

    test "gives a nil base_branch for an unmanaged worktree" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      worktree = add_worktree(repository, "review", managed?: false)

      assert {:ok, state} = Capabilities.repo_state(worktree, @node_name, @field_name)
      assert state.checkout == :worktree
      assert state.worktree_name == "review"
      assert state.base_branch == nil
    end

    test "sets repo_root to the main path when inspected from inside a worktree" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      worktree = add_worktree(repository, "feature", managed?: false)

      assert {:ok, state} = Capabilities.repo_state(worktree, @node_name, @field_name)
      assert state.repo_root == repository.root
      refute state.path == state.repo_root
    end

    test "describes a detached HEAD" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      Repository.git!(["-C", repository.root, "checkout", "--detach"])

      assert {:ok, state} = Capabilities.repo_state(repository.root, @node_name, @field_name)
      assert state.current_branch == nil
      assert state.detached? == true
      assert state.upstream_branch == nil
      assert state.ahead == nil
      assert state.behind == nil
    end

    test "gives nil ahead, behind, and upstream when there is no upstream" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert {:ok, state} = Capabilities.repo_state(repository.root, @node_name, @field_name)
      assert state.upstream_branch == nil
      assert state.ahead == nil
      assert state.behind == nil
    end

    test "counts ahead and behind after a local commit and a fetch" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      File.write!(Path.join(repository.root, "README.md"), "local\n")
      Repository.git!(["-C", repository.root, "add", "README.md"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "local"])

      other = Path.join(repository.parent, "other")
      Repository.git!(["clone", "--branch", "main", repository.remote, other])
      Repository.git!(["-C", other, "config", "user.email", "test@example.com"])
      Repository.git!(["-C", other, "config", "user.name", "Domovoy Test"])
      File.write!(Path.join(other, "other.txt"), "other\n")
      Repository.git!(["-C", other, "add", "other.txt"])
      Repository.git!(["-C", other, "commit", "-qm", "other"])
      Repository.git!(["-C", other, "push", "origin", "main"])

      assert {:ok, _output} =
               Capabilities.fetch("origin", repository.root, @node_name, @field_name)

      assert {:ok, state} = Capabilities.repo_state(repository.root, @node_name, @field_name)
      assert state.ahead == 1
      assert state.behind == 1
    end
  end

  describe "conflicts/3" do
    test "reads a both-modified text conflict with stages and hunks" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      diverge(repository.root, "README.md", "feature-side\n", "main-side\n")

      assert {:ok, state} = Capabilities.repo_state(repository.root, @node_name, @field_name)
      assert state.operation == :merging
      assert [%{path: "README.md", kind: :both_modified, code: "UU"} = conflict] = state.conflicts
      assert conflict.stages.base != nil
      assert conflict.stages.ours != nil
      assert conflict.stages.theirs != nil
      assert [%{ours: ["main-side"], theirs: ["feature-side"]}] = conflict.hunks
    end

    test "gives a nil stage for the missing side of a delete/modify conflict" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      File.write!(Path.join(repository.root, "gone.txt"), "keep\n")
      Repository.git!(["-C", repository.root, "add", "gone.txt"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "add gone"])
      Repository.git!(["-C", repository.root, "checkout", "-qb", "feature"])
      File.write!(Path.join(repository.root, "gone.txt"), "changed\n")
      Repository.git!(["-C", repository.root, "add", "gone.txt"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "change gone"])
      Repository.git!(["-C", repository.root, "checkout", "-q", "main"])
      Repository.git!(["-C", repository.root, "rm", "-q", "gone.txt"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "remove gone"])
      merge_ignoring_failure(repository.root)

      assert {:ok, state} = Capabilities.repo_state(repository.root, @node_name, @field_name)
      assert [%{path: "gone.txt", kind: kind} = conflict] = state.conflicts
      assert kind in [:deleted_by_us, :deleted_by_them]
      assert conflict.stages.base != nil
      assert conflict.stages.ours == nil or conflict.stages.theirs == nil
      assert conflict.hunks == []
    end

    test "gives empty hunks for a binary both-modified conflict" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      path = Path.join(repository.root, "blob.bin")
      File.write!(path, <<0, 1, 2>>)
      Repository.git!(["-C", repository.root, "add", "blob.bin"])
      Repository.git!(["-C", repository.root, "commit", "-qm", "add blob"])
      diverge(repository.root, "blob.bin", <<0, 1, 9>>, <<0, 2, 2>>)

      assert {:ok, state} = Capabilities.repo_state(repository.root, @node_name, @field_name)
      assert [%{path: "blob.bin", kind: :both_modified} = conflict] = state.conflicts
      assert conflict.stages.ours != nil
      assert conflict.stages.theirs != nil
      assert conflict.hunks == []
    end

    test "gives empty hunks after markers are edited away without git add" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      diverge(repository.root, "README.md", "ours\n", "theirs\n")
      File.write!(Path.join(repository.root, "README.md"), "resolved\n")

      assert {:ok, state} = Capabilities.repo_state(repository.root, @node_name, @field_name)
      assert [%{path: "README.md", hunks: [], stages: stages}] = state.conflicts
      assert stages.ours != nil
      assert stages.theirs != nil
    end

    test "reports merging with no remaining conflicts after git add" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      diverge(repository.root, "README.md", "ours\n", "theirs\n")
      File.write!(Path.join(repository.root, "README.md"), "resolved\n")
      Repository.git!(["-C", repository.root, "add", "README.md"])

      assert {:ok, state} = Capabilities.repo_state(repository.root, @node_name, @field_name)
      assert state.operation == :merging
      assert state.conflicts == []
    end
  end

  describe "checkout/4" do
    test "checks out an existing local branch" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)
      Repository.git!(["-C", repository.root, "branch", "feature"])

      assert :ok = Capabilities.checkout("feature", repository.root, @node_name, :branch_name)

      assert {:ok, "feature"} =
               Capabilities.current_branch(repository.root, @node_name, @field_name)
    end

    test "gives branch_not_found and does not create a missing branch" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert {:error, %Error{type: :branch_not_found} = error} =
               Capabilities.checkout("missing", repository.root, @node_name, :branch_name)

      assert error.metadata.branch == "missing"
      refute File.exists?(Path.join(repository.root, ".git/refs/heads/missing"))
    end
  end

  describe "create_branch/5" do
    test "creates a branch from HEAD" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert :ok =
               Capabilities.create_branch(
                 "feature",
                 nil,
                 repository.root,
                 @node_name,
                 :branch_name
               )

      assert {:ok, "feature"} =
               Capabilities.current_branch(repository.root, @node_name, @field_name)
    end

    test "fails when the branch already exists" do
      repository = Repository.create!(remote?: false)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert {:error, %Error{type: :git_command_failed}} =
               Capabilities.create_branch("main", nil, repository.root, @node_name, :branch_name)
    end
  end

  describe "track_remote_branch/5" do
    test "gives remote_branch_not_found when the remote branch is missing" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert {:error, %Error{type: :remote_branch_not_found} = error} =
               Capabilities.track_remote_branch(
                 "missing",
                 "origin",
                 repository.root,
                 @node_name,
                 :branch_name
               )

      assert error.metadata.remote == "origin"
      assert error.metadata.branch == "missing"
    end
  end

  @spec add_worktree(Repository.t(), String.t(), keyword()) :: String.t()
  defp add_worktree(repository, name, opts) do
    path = WorktreeMetadata.worktree_path(repository.root, name)
    Repository.git!(["-C", repository.root, "worktree", "add", "-q", "-b", name, path])

    if Keyword.get(opts, :managed?, false) do
      WorktreeMetadata.write_record(Path.join(repository.root, ".git"), name, %{
        path: path,
        branch: name,
        base_branch: "main"
      })
    end

    path
  end

  @spec diverge(String.t(), String.t(), iodata(), iodata()) :: :ok
  defp diverge(root, relative, ours, theirs) do
    Repository.git!(["-C", root, "checkout", "-qb", "feature"])
    File.write!(Path.join(root, relative), ours)
    Repository.git!(["-C", root, "add", relative])
    Repository.git!(["-C", root, "commit", "-qm", "ours"])
    Repository.git!(["-C", root, "checkout", "-q", "main"])
    File.write!(Path.join(root, relative), theirs)
    Repository.git!(["-C", root, "add", relative])
    Repository.git!(["-C", root, "commit", "-qm", "theirs"])
    merge_ignoring_failure(root)
    :ok
  end

  @spec merge_ignoring_failure(String.t()) :: :ok
  defp merge_ignoring_failure(root) do
    System.cmd("git", ["-C", root, "merge", "--no-edit", "feature"], stderr_to_stdout: true)
    :ok
  end
end
