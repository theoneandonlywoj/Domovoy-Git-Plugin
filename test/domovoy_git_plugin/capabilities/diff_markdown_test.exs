defmodule DomovoyGitPlugin.Capabilities.DiffMarkdownTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Capabilities.DiffMarkdown

  doctest DiffMarkdown

  describe "render/2" do
    test "heads the document with the worktree's name, branch, base branch, and path" do
      rendered = DiffMarkdown.render([], metadata(%{}))

      assert rendered =~ "# Worktree feature"
      assert rendered =~ "- Branch: `feature`"
      assert rendered =~ "- Base branch: `main`"
      assert rendered =~ "- Path: `/repo/.worktrees/feature`"
    end

    test "renders a detached worktree without a branch name" do
      rendered = DiffMarkdown.render([], metadata(%{branch: nil}))

      assert rendered =~ "- Branch: _detached_"
    end

    test "says so when there are no changes" do
      assert DiffMarkdown.render([], metadata(%{})) =~ "_No changes._"
    end

    test "renders removals before additions inside a diff fence" do
      files = [%{file: "README.md", hunks: [hunk()]}]

      rendered = DiffMarkdown.render(files, metadata(%{}))

      assert rendered =~ "## README.md"

      assert rendered =~ """
             ```diff
             @@ -1,2 +1,2 @@
             -old line
             +new line
             ```\
             """
    end

    test "renders a file with no hunks as having no changes" do
      rendered = DiffMarkdown.render([%{file: "script.sh", hunks: []}], metadata(%{}))

      assert rendered =~ "## script.sh"
      assert rendered =~ "_No changes._"
    end

    test "separates multiple files and ends with a newline" do
      files = [%{file: "a.ex", hunks: [hunk()]}, %{file: "b.ex", hunks: [hunk()]}]

      rendered = DiffMarkdown.render(files, metadata(%{}))

      assert rendered =~ "## a.ex"
      assert rendered =~ "## b.ex"
      assert String.ends_with?(rendered, "\n")
    end
  end

  @spec metadata(map()) :: map()
  defp metadata(overrides) do
    Map.merge(
      %{
        worktree_name: "feature",
        path: "/repo/.worktrees/feature",
        branch: "feature",
        base_branch: "main"
      },
      overrides
    )
  end

  @spec hunk() :: map()
  defp hunk do
    %{
      header: "@@ -1,2 +1,2 @@",
      old_start_line: 1,
      old_end_line: 2,
      new_start_line: 1,
      new_end_line: 2,
      section: nil,
      added_lines: ["new line"],
      removed_lines: ["old line"]
    }
  end
end
