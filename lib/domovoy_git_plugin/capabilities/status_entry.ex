defmodule DomovoyGitPlugin.Capabilities.StatusEntry do
  @moduledoc """
  One line of `git status --porcelain`, read as a path and two states.

  Git writes two characters before the path. The first character is the state of
  the index. The second character is the state of the working tree. A space
  means that the side did not change. Thus `" M"` is a modified file that is not
  staged, and `"M "` is a modified file that is staged.

  This module gives a name to each character. A caller then reads
  `entry.index` and `entry.worktree` and does not count characters or compare
  spaces. The raw code stays in `entry.code`.

  The module reads each of the two positions on its own. Git writes a merge
  conflict as a pair, for example `"AA"` or `"DD"`. Such an entry gives two
  `:added` states or two `:deleted` states. Use `entry.code` when the pair
  matters.

  The parser is total. An unknown character gives `:unknown`.

  ## Examples

      iex> StatusEntry.parse(" M lib/app.ex")
      %{path: "lib/app.ex", code: " M", index: :unmodified, worktree: :modified}

      iex> StatusEntry.parse("M  lib/staged.ex")
      %{path: "lib/staged.ex", code: "M ", index: :modified, worktree: :unmodified}

      iex> StatusEntry.parse("?? lib/new.ex")
      %{path: "lib/new.ex", code: "??", index: :untracked, worktree: :untracked}

  A staged addition with a later edit reports a different state on each side:

      iex> StatusEntry.parse("AM lib/app.ex")
      %{path: "lib/app.ex", code: "AM", index: :added, worktree: :modified}

  A rename keeps the text that Git writes for the path:

      iex> StatusEntry.parse("R  lib/old.ex -> lib/new.ex")
      %{
        path: "lib/old.ex -> lib/new.ex",
        code: "R ",
        index: :renamed,
        worktree: :unmodified
      }
  """

  alias __MODULE__, as: StatusEntry

  @states [
    :unmodified,
    :added,
    :modified,
    :deleted,
    :renamed,
    :copied,
    :unmerged,
    :untracked,
    :ignored,
    :unknown
  ]

  @typedoc "What happened to one side of a path."
  @type state() ::
          :unmodified
          | :added
          | :modified
          | :deleted
          | :renamed
          | :copied
          | :unmerged
          | :untracked
          | :ignored
          | :unknown

  @typedoc "One changed path, its raw porcelain code, and the state of each side."
  @type t() :: %{path: String.t(), code: String.t(), index: state(), worktree: state()}

  @doc """
  Returns `true` if `value` is a state that this module gives.

  Use this guard to accept an entry that another module made.
  """
  defguard is_state(value) when value in @states

  @doc """
  Returns every state that this module gives.

  ## Examples

      iex> :unmerged in StatusEntry.states()
      true
  """
  @spec states() :: [state()]
  def states, do: @states

  @doc """
  Reads one line of `git status --porcelain` as an entry.

  The line holds the two-character code, one space, and the path. This function
  does not read the disk and it cannot fail.

  ## Examples

      iex> StatusEntry.parse("D  lib/gone.ex")
      %{path: "lib/gone.ex", code: "D ", index: :deleted, worktree: :unmodified}

  ## Equivalent Bash

      git -C /repo status --porcelain
  """
  @spec parse(line :: String.t()) :: StatusEntry.t()
  def parse(line) when is_binary(line) do
    code = String.slice(line, 0, 2)

    %{
      path: String.slice(line, 3..-1//1),
      code: code,
      index: code |> String.at(0) |> state(),
      worktree: code |> String.at(1) |> state()
    }
  end

  @spec state(character :: String.t() | nil) :: state()
  defp state(" "), do: :unmodified
  defp state("A"), do: :added
  defp state("M"), do: :modified
  defp state("D"), do: :deleted
  defp state("R"), do: :renamed
  defp state("C"), do: :copied
  defp state("U"), do: :unmerged
  defp state("?"), do: :untracked
  defp state("!"), do: :ignored
  defp state(_other), do: :unknown
end
