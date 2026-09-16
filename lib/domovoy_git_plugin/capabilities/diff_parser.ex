defmodule DomovoyGitPlugin.Capabilities.DiffParser do
  @moduledoc """
  Parses unified `git diff` text into a structured list of hunks for each file.

  Every Git capability that makes raw diff output uses this module. Tracked
  changes, untracked files and branch comparisons all need the same parser.
  Therefore the parser is here and not in each capability.

  The parser is total. It never raises on unexpected input. It ignores each line
  that it does not know. Thus a diff with binary-file notices, rename headers or
  mode changes gives the hunks that the parser understands. The parser does not
  fail.

  ## Examples

      iex> diff = \"\"\"
      ...> diff --git a/README.md b/README.md
      ...> index 1a2b3c4..5d6e7f8 100644
      ...> --- a/README.md
      ...> +++ b/README.md
      ...> @@ -1,3 +1,4 @@
      ...>  # Domovoy
      ...> -A workflow engine.
      ...> +A workflow engine for Elixir.
      ...> +Built on a node graph.
      ...> \"\"\"
      iex> DiffParser.parse(diff)
      [
        %{
          file: "README.md",
          hunks: [
            %{
              header: "@@ -1,3 +1,4 @@",
              old_start_line: 1,
              old_end_line: 3,
              new_start_line: 1,
              new_end_line: 4,
              section: nil,
              added_lines: ["A workflow engine for Elixir.", "Built on a node graph."],
              removed_lines: ["A workflow engine."]
            }
          ]
        }
      ]

  The parser drops the unchanged context lines. It keeps the added lines and the
  removed lines apart, each in its original order.
  """

  alias __MODULE__, as: DiffParser

  @typedoc """
  One hunk of a file diff, with its added and removed lines in order.

  If one side of the hunk holds no lines, the two line numbers of that side are
  `nil`. An added file has no old lines. A deleted file has no new lines. The
  `header` keeps the raw text of Git in each case.
  """
  @type hunk() :: %{
          header: String.t(),
          old_start_line: integer() | nil,
          old_end_line: integer() | nil,
          new_start_line: integer() | nil,
          new_end_line: integer() | nil,
          section: String.t() | nil,
          added_lines: [String.t()],
          removed_lines: [String.t()]
        }

  @typedoc "Every hunk recorded for a single file."
  @type file_diff() :: %{file: String.t(), hunks: [hunk()]}

  @typedoc "The accumulator that moves through the lines of the diff."
  @type parse_state() :: %{
          files: [file_diff()],
          current_file: file_diff() | nil,
          current_hunk: hunk() | nil
        }

  @hunk_header_pattern ~r/^@@ -(?<old_start_line>\d+)(?:,(?<old_count>\d+))? \+(?<new_start_line>\d+)(?:,(?<new_count>\d+))? @@(?: (?<section>.*))?$/

  @doc """
  Parses unified `git diff` text into a list of `t:file_diff/0` entries.

  ## Examples

  A diff with more than one hunk keeps the hunks in file order. The text after
  the second `@@` becomes the `:section` of the hunk:

      iex> diff = \"\"\"
      ...> diff --git a/lib/app.ex b/lib/app.ex
      ...> --- a/lib/app.ex
      ...> +++ b/lib/app.ex
      ...> @@ -10,4 +10,4 @@ defmodule App do
      ...> -  def old, do: :ok
      ...> +  def new, do: :ok
      ...> @@ -30,3 +30,3 @@ defmodule App do
      ...> -  defp helper, do: 1
      ...> +  defp helper, do: 2
      ...> \"\"\"
      iex> DiffParser.parse(diff)
      [
        %{
          file: "lib/app.ex",
          hunks: [
            %{
              header: "@@ -10,4 +10,4 @@ defmodule App do",
              old_start_line: 10,
              old_end_line: 13,
              new_start_line: 10,
              new_end_line: 13,
              section: "defmodule App do",
              added_lines: ["  def new, do: :ok"],
              removed_lines: ["  def old, do: :ok"]
            },
            %{
              header: "@@ -30,3 +30,3 @@ defmodule App do",
              old_start_line: 30,
              old_end_line: 32,
              new_start_line: 30,
              new_end_line: 32,
              section: "defmodule App do",
              added_lines: ["  defp helper, do: 2"],
              removed_lines: ["  defp helper, do: 1"]
            }
          ]
        }
      ]

  An added file has no old lines. Git writes `-0,0` for that side, and the
  parser gives `nil` for the two old line numbers:

      iex> diff = \"\"\"
      ...> diff --git a/lib/new.ex b/lib/new.ex
      ...> new file mode 100644
      ...> --- /dev/null
      ...> +++ b/lib/new.ex
      ...> @@ -0,0 +1,3 @@
      ...> +defmodule New do
      ...> +  @moduledoc false
      ...> +end
      ...> \"\"\"
      iex> DiffParser.parse(diff)
      [
        %{
          file: "lib/new.ex",
          hunks: [
            %{
              header: "@@ -0,0 +1,3 @@",
              old_start_line: nil,
              old_end_line: nil,
              new_start_line: 1,
              new_end_line: 3,
              section: nil,
              added_lines: ["defmodule New do", "  @moduledoc false", "end"],
              removed_lines: []
            }
          ]
        }
      ]

  A binary file has a header but no hunks. The parser reports the file with an
  empty hunk list. It does not fail:

      iex> diff = \"\"\"
      ...> diff --git a/logo.png b/logo.png
      ...> Binary files a/logo.png and b/logo.png differ
      ...> \"\"\"
      iex> DiffParser.parse(diff)
      [%{file: "logo.png", hunks: []}]

  Text without a `diff --git` header gives an empty list:

      iex> DiffParser.parse("nothing to commit, working tree clean\\n")
      []

      iex> DiffParser.parse("")
      []

  ## Equivalent Bash

      git diff HEAD
  """
  @spec parse(diff_text :: String.t()) :: [DiffParser.file_diff()]
  def parse(diff_text) when is_binary(diff_text) do
    diff_text
    |> String.split("\n")
    |> Enum.reduce(%{files: [], current_file: nil, current_hunk: nil}, &process_line/2)
    |> finalize_state()
  end

  @spec process_line(line :: String.t(), state :: parse_state()) :: parse_state()
  defp process_line("diff --git " <> rest, state) do
    state = save_current_file(state)
    %{state | current_file: %{file: diff_filename(rest), hunks: []}}
  end

  defp process_line("@@ " <> _rest = line, state) do
    state = save_current_hunk(state)
    hunk = line |> parse_hunk_header() |> Map.merge(%{added_lines: [], removed_lines: []})
    %{state | current_hunk: hunk}
  end

  defp process_line("---" <> _rest, state), do: state
  defp process_line("+++" <> _rest, state), do: state

  defp process_line("+" <> line, %{current_hunk: hunk} = state) when not is_nil(hunk) do
    %{state | current_hunk: Map.update!(hunk, :added_lines, fn lines -> [line | lines] end)}
  end

  defp process_line("-" <> line, %{current_hunk: hunk} = state) when not is_nil(hunk) do
    %{state | current_hunk: Map.update!(hunk, :removed_lines, fn lines -> [line | lines] end)}
  end

  defp process_line(_line, state), do: state

  @spec parse_hunk_header(line :: String.t()) :: map()
  defp parse_hunk_header(line) do
    %{
      "old_start_line" => old_start_line,
      "old_count" => old_count,
      "new_start_line" => new_start_line,
      "new_count" => new_count,
      "section" => section
    } = Regex.named_captures(@hunk_header_pattern, line)

    {old_start_line, old_end_line} =
      old_start_line |> String.to_integer() |> line_range(count(old_count))

    {new_start_line, new_end_line} =
      new_start_line |> String.to_integer() |> line_range(count(new_count))

    %{
      header: line,
      old_start_line: old_start_line,
      old_end_line: old_end_line,
      new_start_line: new_start_line,
      new_end_line: new_end_line,
      section: section(section)
    }
  end

  @spec line_range(start_line :: integer(), count :: integer()) ::
          {integer() | nil, integer() | nil}
  defp line_range(_start_line, 0), do: {nil, nil}
  defp line_range(start_line, count), do: {start_line, start_line + count - 1}

  @spec count(value :: String.t()) :: integer()
  defp count(""), do: 1
  defp count(value), do: String.to_integer(value)

  @spec section(value :: String.t()) :: String.t() | nil
  defp section(""), do: nil
  defp section(value), do: value

  @spec diff_filename(header_rest :: String.t()) :: String.t()
  defp diff_filename(header_rest) do
    case Regex.run(~r/^a\/(.+?) b\/(.+)$/, header_rest) do
      [_match, _a_path, b_path] ->
        b_path

      nil ->
        header_rest |> String.split(" ") |> List.last() |> String.replace_leading("b/", "")
    end
  end

  @spec save_current_hunk(state :: parse_state()) :: parse_state()
  defp save_current_hunk(%{current_file: file, current_hunk: hunk} = state)
       when not is_nil(file) and not is_nil(hunk) do
    finished_hunk = %{
      hunk
      | added_lines: Enum.reverse(hunk.added_lines),
        removed_lines: Enum.reverse(hunk.removed_lines)
    }

    updated_file = Map.update!(file, :hunks, fn hunks -> [finished_hunk | hunks] end)

    %{state | current_file: updated_file, current_hunk: nil}
  end

  defp save_current_hunk(state), do: state

  @spec save_current_file(state :: parse_state()) :: parse_state()
  defp save_current_file(state) do
    state = save_current_hunk(state)

    case state.current_file do
      nil ->
        state

      file ->
        finished_file = %{file | hunks: Enum.reverse(file.hunks)}
        %{state | files: [finished_file | state.files], current_file: nil}
    end
  end

  @spec finalize_state(state :: parse_state()) :: [file_diff()]
  defp finalize_state(state) do
    state |> save_current_file() |> Map.get(:files) |> Enum.reverse()
  end
end
