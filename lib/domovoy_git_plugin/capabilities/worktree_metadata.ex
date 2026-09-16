defmodule DomovoyGitPlugin.Capabilities.WorktreeMetadata do
  @moduledoc """
  Parses `git worktree list --porcelain`. Reads and writes the record that
  Domovoy keeps for each worktree that it creates.

  Git records the path, the `HEAD` and the branch of a worktree. Git does not
  record the ref that the worktree started from. Domovoy needs this base branch
  to compare a worktree with its start point. Therefore
  `DomovoyGitPlugin.Runner.WorktreeCreate` writes the base branch to
  `<git-common-dir>/domovoy/worktrees/<worktree_name>.json`. The record stays in
  `.git/`. Thus the record can never occur in a diff of the worktree that it
  describes.

  A worktree that a person made with `git worktree add` has no record. Such a
  worktree gives a base branch of `nil`. It does not give an error.

  This module only parses text and reads files. The Git commands that make the
  porcelain output are in `DomovoyGitPlugin.Capabilities`.
  """

  alias __MODULE__, as: WorktreeMetadata

  @typedoc "The main root of a repository and the Git directory that its worktrees share."
  @type repository() :: %{root: String.t(), git_common_directory: String.t()}

  @typedoc "One worktree as `git worktree list --porcelain` reports it."
  @type worktree_record() :: %{path: String.t(), head: String.t() | nil, branch: String.t() | nil}

  @worktrees_directory ".worktrees"
  @record_directory ["domovoy", "worktrees"]

  @doc """
  Returns the absolute path of the worktree `worktree_name` for the repository
  at `root`.

  ## Examples

      iex> WorktreeMetadata.worktree_path("/repo", "feature")
      "/repo/.worktrees/feature"

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec worktree_path(root :: String.t(), worktree_name :: String.t()) :: String.t()
  def worktree_path(root, worktree_name) when is_binary(root) and is_binary(worktree_name),
    do: Path.join([root, @worktrees_directory, worktree_name])

  @doc """
  Returns the directory that holds every managed worktree of the repository at
  `root`.

  ## Examples

      iex> WorktreeMetadata.worktrees_root("/repo")
      "/repo/.worktrees"

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec worktrees_root(root :: String.t()) :: String.t()
  def worktrees_root(root) when is_binary(root), do: Path.join(root, @worktrees_directory)

  @doc """
  Returns the root of the main checkout from a list of parsed records.

  `git worktree list --porcelain` always reports the main worktree first. It
  reports the main worktree in the same way from every checkout. Therefore this
  function is the only correct way to find `.worktrees/` from a linked worktree.
  `git rev-parse --show-toplevel` gives the path of the linked worktree instead.

  ## Examples

      iex> records = [
      ...>   %{path: "/repo", head: "abc123", branch: "main"},
      ...>   %{path: "/repo/.worktrees/feature", head: "def456", branch: "feature"}
      ...> ]
      iex> WorktreeMetadata.main_root(records)
      "/repo"

  ## Equivalent Bash

      git worktree list --porcelain | head -1
  """
  @spec main_root(records :: [worktree_record(), ...]) :: String.t()
  def main_root([%{path: path} | _rest]), do: path

  @doc """
  Parses `git worktree list --porcelain` text into one record for each worktree.

  A blank line separates the records. Each record has a `worktree <path>` line
  and a `HEAD <sha>` line. Then it has a `branch refs/heads/<name>` line or a
  `detached` line. A detached worktree gives `branch: nil`. This function
  ignores the `bare`, `locked` and `prunable` lines.

  ## Examples

      iex> porcelain = \"\"\"
      ...> worktree /repo
      ...> HEAD 1a2b3c4d5e6f
      ...> branch refs/heads/main
      ...>
      ...> worktree /repo/.worktrees/feature
      ...> HEAD 7f8e9d0c1b2a
      ...> branch refs/heads/bro-19-add-metadata
      ...> \"\"\"
      iex> WorktreeMetadata.parse_porcelain(porcelain)
      [
        %{path: "/repo", head: "1a2b3c4d5e6f", branch: "main"},
        %{
          path: "/repo/.worktrees/feature",
          head: "7f8e9d0c1b2a",
          branch: "bro-19-add-metadata"
        }
      ]

  A detached worktree gives `branch: nil`:

      iex> porcelain = \"\"\"
      ...> worktree /repo/.worktrees/review
      ...> HEAD 0f1e2d3c4b5a
      ...> detached
      ...> \"\"\"
      iex> WorktreeMetadata.parse_porcelain(porcelain)
      [%{path: "/repo/.worktrees/review", head: "0f1e2d3c4b5a", branch: nil}]

  Text without a `worktree` line gives an empty list:

      iex> WorktreeMetadata.parse_porcelain("")
      []

  ## Equivalent Bash

      git worktree list --porcelain
  """
  @spec parse_porcelain(porcelain_output :: String.t()) :: [worktree_record()]
  def parse_porcelain(porcelain_output) when is_binary(porcelain_output) do
    porcelain_output
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.flat_map(&parse_record/1)
  end

  @doc """
  Splits `git rev-parse --show-toplevel --git-common-dir` output into a
  repository.

  `--git-common-dir` gives a path that is relative to the *current directory*.
  From the root the path is `.git`. From `lib/` the path is `../.git`. Therefore
  this function expands the path against `working_directory`. It does not expand
  the path against the root of the repository.

  ## Examples

      iex> WorktreeMetadata.parse_repository("/repo\\n.git\\n", "/repo")
      {:ok, %{root: "/repo", git_common_directory: "/repo/.git"}}

  From a subdirectory, Git gives a relative path that needs that subdirectory:

      iex> WorktreeMetadata.parse_repository("/repo\\n../.git\\n", "/repo/lib")
      {:ok, %{root: "/repo", git_common_directory: "/repo/.git"}}

  Output with fewer than two lines gives `:error`:

      iex> WorktreeMetadata.parse_repository("/repo\\n", "/repo")
      :error

  ## Equivalent Bash

      git -C /repo rev-parse --show-toplevel --git-common-dir
  """
  @spec parse_repository(porcelain_output :: String.t(), working_directory :: String.t()) ::
          {:ok, repository()} | :error
  def parse_repository(porcelain_output, working_directory)
      when is_binary(porcelain_output) and is_binary(working_directory) do
    case porcelain_output |> String.split("\n", trim: true) |> Enum.map(&String.trim/1) do
      [root, git_common_directory | _rest] ->
        {:ok,
         %{
           root: Path.expand(root),
           git_common_directory: Path.expand(git_common_directory, working_directory)
         }}

      _other ->
        :error
    end
  end

  @doc """
  Returns the base branch that the record for `worktree_name` holds.

  If the record does not exist, or if this function cannot decode the record,
  the result is `nil`. A worktree that a person made by hand has no record.
  Therefore a missing record gives `nil` and not an error.

  ## Examples

      WorktreeMetadata.read_base_branch("/repo/.git", "feature")
      #=> "main"

      WorktreeMetadata.read_base_branch("/repo/.git", "made-by-hand")
      #=> nil

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec read_base_branch(git_common_directory :: String.t(), worktree_name :: String.t()) ::
          String.t() | nil
  def read_base_branch(git_common_directory, worktree_name)
      when is_binary(git_common_directory) and is_binary(worktree_name) do
    with {:ok, contents} <-
           git_common_directory |> WorktreeMetadata.record_path(worktree_name) |> File.read(),
         {:ok, %{"base_branch" => base_branch}} when is_binary(base_branch) <-
           JSON.decode(contents) do
      base_branch
    else
      _other -> nil
    end
  end

  @doc """
  Writes the record for `worktree_name`. Makes the directory of the record if
  the directory does not exist.

  ## Examples

      WorktreeMetadata.write_record("/repo/.git", "feature", %{
        path: "/repo/.worktrees/feature",
        branch: "bro-19-add-metadata",
        base_branch: "main"
      })
      #=> :ok

  The function writes this JSON to
  `/repo/.git/domovoy/worktrees/feature.json`:

      {"worktree_name":"feature","path":"/repo/.worktrees/feature",
       "branch":"bro-19-add-metadata","base_branch":"main"}

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec write_record(
          git_common_directory :: String.t(),
          worktree_name :: String.t(),
          attributes :: %{path: String.t(), branch: String.t(), base_branch: String.t()}
        ) :: :ok | {:error, File.posix()}
  def write_record(git_common_directory, worktree_name, attributes)
      when is_binary(git_common_directory) and is_binary(worktree_name) do
    path = WorktreeMetadata.record_path(git_common_directory, worktree_name)

    contents =
      JSON.encode!(%{
        "worktree_name" => worktree_name,
        "path" => attributes.path,
        "branch" => attributes.branch,
        "base_branch" => attributes.base_branch
      })

    with :ok <- path |> Path.dirname() |> File.mkdir_p() do
      File.write(path, contents)
    end
  end

  @doc """
  Deletes the record for `worktree_name`. Gives `:ok` also when no record
  exists.

  ## Examples

      WorktreeMetadata.delete_record("/repo/.git", "feature")
      #=> :ok

      WorktreeMetadata.delete_record("/repo/.git", "never-existed")
      #=> :ok

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec delete_record(git_common_directory :: String.t(), worktree_name :: String.t()) :: :ok
  def delete_record(git_common_directory, worktree_name)
      when is_binary(git_common_directory) and is_binary(worktree_name) do
    case git_common_directory |> WorktreeMetadata.record_path(worktree_name) |> File.rm() do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  @doc """
  Returns the absolute path of the record file for `worktree_name`.

  ## Examples

      iex> WorktreeMetadata.record_path("/repo/.git", "feature")
      "/repo/.git/domovoy/worktrees/feature.json"

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec record_path(git_common_directory :: String.t(), worktree_name :: String.t()) :: String.t()
  def record_path(git_common_directory, worktree_name)
      when is_binary(git_common_directory) and is_binary(worktree_name),
      do: Path.join([git_common_directory | @record_directory] ++ ["#{worktree_name}.json"])

  @spec parse_record(record_block :: String.t()) :: [worktree_record()]
  defp parse_record(record_block) do
    fields =
      record_block
      |> String.split("\n", trim: true)
      |> Enum.reduce(%{path: nil, head: nil, branch: nil}, &put_field/2)

    if fields.path, do: [fields], else: []
  end

  @spec put_field(line :: String.t(), fields :: worktree_record()) :: worktree_record()
  defp put_field("worktree " <> path, fields),
    do: %{fields | path: path |> String.trim() |> Path.expand()}

  defp put_field("HEAD " <> head, fields), do: %{fields | head: String.trim(head)}

  defp put_field("branch " <> ref, fields),
    do: %{fields | branch: ref |> String.trim() |> String.replace_prefix("refs/heads/", "")}

  defp put_field(_line, fields), do: fields
end
