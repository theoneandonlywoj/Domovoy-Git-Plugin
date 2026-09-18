defmodule DomovoyGitPlugin.ErrorTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Error, as: GitError

  require GitError

  doctest GitError

  @plugin_directory Path.expand("../../lib/domovoy_git_plugin", __DIR__)

  @node_name "worktree_create"
  @field_name :worktree_name

  describe "types/0" do
    test "names each type exactly once" do
      assert GitError.types() == Enum.uniq(GitError.types())
      assert length(GitError.types()) == 14
    end

    test "names every type the builders give, and no other" do
      assert built() |> Enum.map(& &1.type) |> Enum.uniq() |> Enum.sort() ==
               Enum.sort(GitError.types())
    end

    test "every error names the node and the field" do
      assert Enum.all?(built(), &(&1.metadata.node_name == @node_name))
      assert Enum.all?(built(), &(&1.metadata.field_name == @field_name))
    end

    test "no error carries a node, a node input, or a resolved value" do
      for error <- built() do
        refute Map.has_key?(error.metadata, :node)
        refute Map.has_key?(error.metadata, :node_input)
        refute Map.has_key?(error.metadata, :value)
      end
    end
  end

  describe "is_type/1" do
    test "accepts each type of the Git plugin" do
      assert Enum.all?(GitError.types(), fn type -> GitError.is_type(type) end)
    end

    test "rejects a type of another plugin" do
      refute GitError.is_type(:github_request_failed)
      refute GitError.is_type("git_command_failed")
    end
  end

  describe "the plugin builds each error here" do
    test "no other module of the Git plugin calls DomovoyCore.Error.new/1" do
      sources =
        @plugin_directory
        |> Path.join("**/*.ex")
        |> Path.wildcard()
        |> Enum.reject(&(Path.basename(&1) == "error.ex"))

      assert sources != [], "no sources found under " <> @plugin_directory

      offenders =
        sources
        |> Enum.filter(&(&1 |> File.read!() |> String.contains?("Error.new(%{")))
        |> Enum.map(&Path.relative_to(&1, @plugin_directory))

      assert offenders == [],
             "these modules build errors outside DomovoyGitPlugin.Error: " <>
               Enum.join(offenders, ", ")
    end

    test "no module of the Git plugin reads a node input" do
      offenders =
        @plugin_directory
        |> Path.join("**/*.ex")
        |> Path.wildcard()
        |> Enum.filter(&(&1 |> File.read!() |> String.contains?("node_input")))
        |> Enum.map(&Path.relative_to(&1, @plugin_directory))

      assert offenders == [],
             "these modules still name a node input: " <> Enum.join(offenders, ", ")
    end
  end

  describe "command_failed/4" do
    test "keeps the command with git in front" do
      error = GitError.command_failed("fatal", ["status", "--short"], @node_name, @field_name)

      assert error.type == :git_command_failed
      assert error.reason == "fatal"
      assert error.metadata.command == ["git", "status", "--short"]
    end
  end

  describe "worktree_not_registered/4" do
    test "carries a nil path when the repository listed no worktree" do
      error = GitError.worktree_not_registered("feature", nil, @node_name, @field_name)

      assert error.type == :worktree_not_registered
      assert error.metadata.worktree_name == "feature"
      assert error.metadata.path == nil
    end
  end

  @spec built() :: [DomovoyCore.Error.t()]
  defp built do
    [
      GitError.command_failed("fatal", ["status"], @node_name, @field_name),
      GitError.missing_input(@node_name, @field_name),
      GitError.create_worktree_directory_failed(
        :eacces,
        "/repo/.worktrees",
        @node_name,
        @field_name
      ),
      GitError.repository_not_resolved("/tmp/plain", @node_name, @field_name),
      GitError.worktree_not_registered(
        "feature",
        "/repo/.worktrees/feature",
        @node_name,
        @field_name
      ),
      GitError.worktree_already_exists(
        "feature",
        "/repo/.worktrees/feature",
        @node_name,
        @field_name
      ),
      GitError.worktree_not_found(@node_name, @field_name),
      GitError.current_branch_not_found(@node_name, @field_name),
      GitError.write_worktree_record_failed(:eacces, "bro-19", @node_name, @field_name),
      GitError.worktree_diff_failed("no base branch", @node_name, @field_name),
      GitError.branch_name_not_found(@node_name, @field_name),
      GitError.unsupported_operation("rebase", @node_name, @field_name),
      GitError.branch_not_found("feature", @node_name, @field_name),
      GitError.remote_branch_not_found("origin", "feature", @node_name, @field_name)
    ]
  end
end
