defmodule DomovoyGitPlugin.Runner.WorktreeDirectoryTest do
  use ExUnit.Case, async: true

  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.WorktreeDirectory
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Type.Worktree, as: WorktreeType

  doctest WorktreeDirectory

  @moduletag :tmp_dir

  test "returns the directory from the complete worktree value", %{tmp_dir: directory} do
    node =
      Node.new(%{
        name: "worktree_directory",
        runner: WorktreeDirectory,
        type: DirectoryType,
        bind: %{worktree: {"worktree", WorktreeType}}
      })

    worktree =
      Value.cast!(
        %{
          repo_root: Path.dirname(directory),
          name: Path.basename(directory),
          path: directory,
          exists?: true,
          created?: false,
          branch: "feature"
        },
        WorktreeType
      )

    assert %Value{value: ^directory, type: DirectoryType} =
             NodeRunner.run(node, %{"worktree" => worktree})
  end
end
