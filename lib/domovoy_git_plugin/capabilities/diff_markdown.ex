defmodule DomovoyGitPlugin.Capabilities.DiffMarkdown do
  @moduledoc """
  Renders the parsed output of `DomovoyGitPlugin.Capabilities.DiffParser` as
  Markdown for a person.

  Use this module when a worktree diff goes to a person and not to another node.
  The module takes data that is already parsed and gives a string. Therefore it
  never runs a command and it cannot fail.

  `DiffParser` keeps the added lines and the removed lines of a hunk apart. It
  also drops the unchanged context between them. Therefore a rendered hunk shows
  the removed lines first and the added lines second, below the original `@@`
  header.

  ## Examples

  A worktree with one changed file renders this document. The inner fence is
  part of the output, so the whole example is an indented block:

      # Worktree bro-19

      - Branch: `bro-19-add-metadata`
      - Base branch: `main`
      - Path: `/repo/.worktrees/bro-19`

      ## lib/app.ex

      ```diff
      @@ -10,3 +10,3 @@ defmodule App do
      -  def old, do: :ok
      +  def new, do: :ok
      ```

  A worktree without changes renders its heading and then `_No changes._`. A
  detached worktree renders `_detached_` in the place of a branch name. The
  `render/2` documentation shows both of these outputs as doctests.
  """

  alias __MODULE__, as: DiffMarkdown

  alias DomovoyGitPlugin.Capabilities.DiffParser

  @typedoc "The worktree that a rendered diff describes."
  @type metadata() :: %{
          worktree_name: String.t(),
          path: String.t(),
          branch: String.t() | nil,
          base_branch: String.t()
        }

  @no_changes "_No changes._"
  @detached "_detached_"

  @doc """
  Renders `files` as a Markdown document. The name, the branch, the base branch
  and the path of the worktree make the heading.

  A worktree without changes renders its heading and then `#{@no_changes}`. A
  detached worktree renders `#{@detached}` in the place of a branch name.

  ## Examples

      iex> metadata = %{
      ...>   worktree_name: "bro-19",
      ...>   path: "/repo/.worktrees/bro-19",
      ...>   branch: "bro-19-add-metadata",
      ...>   base_branch: "main"
      ...> }
      iex> hunk = %{
      ...>   header: "@@ -10,3 +10,3 @@ defmodule App do",
      ...>   old_start_line: 10,
      ...>   old_end_line: 12,
      ...>   new_start_line: 10,
      ...>   new_end_line: 12,
      ...>   section: "defmodule App do",
      ...>   added_lines: ["  def new, do: :ok"],
      ...>   removed_lines: ["  def old, do: :ok"]
      ...> }
      iex> files = [%{file: "lib/app.ex", hunks: [hunk]}]
      iex> DiffMarkdown.render(files, metadata) |> String.split("\\n")
      ["# Worktree bro-19", "",
       "- Branch: `bro-19-add-metadata`", "- Base branch: `main`",
       "- Path: `/repo/.worktrees/bro-19`", "",
       "## lib/app.ex", "",
       "```diff", "@@ -10,3 +10,3 @@ defmodule App do",
       "-  def old, do: :ok", "+  def new, do: :ok", "```", ""]

  A worktree without changes renders only the heading and `#{@no_changes}`:

      iex> metadata = %{
      ...>   worktree_name: "bro-19",
      ...>   path: "/repo/.worktrees/bro-19",
      ...>   branch: "bro-19-add-metadata",
      ...>   base_branch: "main"
      ...> }
      iex> DiffMarkdown.render([], metadata) |> String.split("\\n") |> Enum.take(-2)
      ["_No changes._", ""]

  A detached worktree renders `#{@detached}` in the place of a branch name:

      iex> metadata = %{
      ...>   worktree_name: "review",
      ...>   path: "/repo/.worktrees/review",
      ...>   branch: nil,
      ...>   base_branch: "main"
      ...> }
      iex> DiffMarkdown.render([], metadata) |> String.split("\\n") |> Enum.at(2)
      "- Branch: _detached_"

  A file without hunks, such as a binary file, renders its own heading and then
  `#{@no_changes}`:

      iex> metadata = %{
      ...>   worktree_name: "bro-19",
      ...>   path: "/repo/.worktrees/bro-19",
      ...>   branch: "bro-19-add-metadata",
      ...>   base_branch: "main"
      ...> }
      iex> DiffMarkdown.render([%{file: "logo.png", hunks: []}], metadata)
      ...> |> String.split("\\n")
      ...> |> Enum.drop(6)
      ["## logo.png", "", "_No changes._", ""]

  This is a Domovoy workflow capability and has no Bash equivalent.
  """
  @spec render(files :: [DiffParser.file_diff()], metadata :: DiffMarkdown.metadata()) ::
          String.t()
  def render(files, metadata) when is_list(files) and is_map(metadata) do
    Enum.join([heading(metadata), body(files)], "\n\n") <> "\n"
  end

  @spec heading(metadata :: metadata()) :: String.t()
  defp heading(metadata) do
    """
    # Worktree #{metadata.worktree_name}

    - Branch: #{code(metadata.branch) || @detached}
    - Base branch: #{code(metadata.base_branch)}
    - Path: #{code(metadata.path)}\
    """
  end

  @spec body(files :: [DiffParser.file_diff()]) :: String.t()
  defp body([]), do: @no_changes
  defp body(files), do: Enum.map_join(files, "\n\n", &file_section/1)

  @spec file_section(file_diff :: DiffParser.file_diff()) :: String.t()
  defp file_section(%{file: file, hunks: hunks}), do: "## #{file}\n\n" <> hunks_body(hunks)

  @spec hunks_body(hunks :: [DiffParser.hunk()]) :: String.t()
  defp hunks_body([]), do: @no_changes
  defp hunks_body(hunks), do: Enum.map_join(hunks, "\n\n", &hunk_block/1)

  @spec hunk_block(hunk :: DiffParser.hunk()) :: String.t()
  defp hunk_block(hunk) do
    removed = Enum.map(hunk.removed_lines, fn line -> "-" <> line end)
    added = Enum.map(hunk.added_lines, fn line -> "+" <> line end)

    Enum.join(["```diff", hunk.header] ++ removed ++ added ++ ["```"], "\n")
  end

  @spec code(value :: String.t() | nil) :: String.t() | nil
  defp code(nil), do: nil
  defp code(value), do: "`#{value}`"
end
