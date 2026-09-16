defmodule DomovoyGitPlugin.Capabilities do
  @moduledoc """
  The Git capabilities that the managed worktree workflows of Domovoy reuse.

  A capability takes plain arguments and gives a plain result. It does not know
  about the graph. A runner turns its `Input` struct into those arguments.
  Therefore the same capability serves many runners.

  Every command goes through `DomovoyCore.Shell` as a list of arguments. No command
  goes through a shell. Thus a branch name or a path with special characters
  cannot become part of a command.

  A command that fails gives `{:error, error}`, where `error` is a
  `DomovoyCore.Error` from `DomovoyGitPlugin.Error`. The error keeps the message
  of Git. Therefore the caller reads the explanation of Git and not a new
  message. A runner gives that tuple back as its result, and a `with` chain
  passes it through without an `else`. Each capability that can fail takes
  `node_name` and `field_name`. The error carries these two names, so a reader
  sees which node failed and which input it read.

  The functions that parse text and read records are in
  `DomovoyGitPlugin.Capabilities.WorktreeMetadata`,
  `DomovoyGitPlugin.Capabilities.DiffParser` and
  `DomovoyGitPlugin.Capabilities.DiffMarkdown`.
  """

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Shell
  alias DomovoyGitPlugin.Capabilities.DiffParser
  alias DomovoyGitPlugin.Capabilities.StatusEntry
  alias DomovoyGitPlugin.Capabilities.WorktreeMetadata
  alias DomovoyGitPlugin.Error, as: GitError
  alias DomovoyGitPlugin.Type.StatusEntries, as: StatusEntriesType
  alias DomovoyGitPlugin.Type.Worktree, as: WorktreeType
  alias DomovoyGitPlugin.Type.WorktreeDiff, as: WorktreeDiffType

  @type result() :: {:ok, String.t()} | failure()
  @type command_output_result() :: {:ok, String.t()} | failure()

  @typedoc "The failure of a capability. The error comes from `DomovoyGitPlugin.Error`."
  @type failure() :: {:error, Error.t()}

  @typedoc "Where a branch is. `:local` is the disk, `:remote` is `origin`."
  @type branch_location() :: :local | :remote | :new

  @git_timeout 30_000

  @doc """
  Resolves `working_directory` to its Git repository root.

  For example, `"/Users/example/project/lib"` gives
  `{:ok, "/Users/example/project"}`. A Git command failure gives
  `{:error, error}` with the node name and the field name in the error.

  ## Equivalent Bash

      git -C /repo/lib rev-parse --show-toplevel
  """
  @spec repository_root(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: result()
  def repository_root(working_directory, node_name, field_name)
      when is_binary(working_directory) do
    with {:ok, repo_root} <-
           run_command(["rev-parse", "--show-toplevel"], working_directory, node_name, field_name) do
      {:ok, String.trim(repo_root)}
    end
  end

  @doc """
  Lists all worktrees registered for `repo_root` in Git's porcelain format.

  Given `"/Users/example/project"`, it returns output such as
  `{:ok, "worktree /Users/example/project\\nHEAD ...\\nbranch refs/heads/main\\n"}`.

  ## Equivalent Bash

      git worktree list --porcelain
  """
  @spec worktree_list(
          repo_root :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: result()
  def worktree_list(repo_root, node_name, field_name) when is_binary(repo_root) do
    run_command(["worktree", "list", "--porcelain"], repo_root, node_name, field_name)
  end

  @doc """
  Returns the checked-out branch name for `working_directory`.

  For example, a repository checked out on `"main"` returns `{:ok, "main"}`.
  A detached HEAD returns a `current_branch_not_found` error.

  ## Equivalent Bash

      git -C /repo branch --show-current
  """
  @spec current_branch(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: result()
  def current_branch(working_directory, node_name, field_name)
      when is_binary(working_directory) do
    with {:ok, output} <-
           run_command(["branch", "--show-current"], working_directory, node_name, field_name),
         branch <- String.trim(output),
         true <- branch != "" do
      {:ok, branch}
    else
      false -> {:error, GitError.current_branch_not_found(node_name, field_name)}
      {:error, %Error{}} = failure -> failure
    end
  end

  @doc """
  Runs a Git command through `DomovoyCore.Shell` and returns its combined output.

  For example, `run_command(["status", "--short"], "/repo", "status", :working_directory)`
  returns `{:ok, " M README.md\\n"}`. A non-zero exit, a timeout, and a failure
  to spawn Git all return a `git_command_failed` error with the message of the
  shell.

  ## Equivalent Bash

      git -C /repo status --short
  """
  @spec run_command(
          args :: [String.t()],
          cwd :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name(),
          opts :: keyword()
        ) :: command_output_result()
  def run_command(args, cwd, node_name, field_name, opts \\ []) do
    shell_opts = Keyword.merge([cd: cwd, timeout: @git_timeout], opts)

    case Shell.run("git", args, shell_opts) do
      {:ok, output} -> {:ok, output}
      {:error, reason} -> {:error, GitError.command_failed(reason, args, node_name, field_name)}
    end
  end

  @doc """
  Returns whether `ref` exists in the repository checked out at `cwd`.

  For example, `branch_exists?("refs/heads/main", "/repo", "check", :worktree)`
  returns `{:ok, true}` when the branch exists and `{:ok, false}` when it does
  not.

  `git for-each-ref` is used rather than `git show-ref --verify` because it
  reports absence by printing nothing and still exiting `0`. `DomovoyCore.Shell`
  reports only success or failure, so a command that signals its answer through
  the exit status cannot be read through it.

  ## Equivalent Bash

      git -C /repo for-each-ref --format=%(refname) refs/heads/main
  """
  @spec branch_exists?(
          ref :: String.t(),
          cwd :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, boolean()} | failure()
  def branch_exists?(ref, cwd, node_name, field_name) when is_binary(ref) and is_binary(cwd) do
    args = ["-C", cwd, "for-each-ref", "--format=%(refname)", ref]

    case Shell.run("git", args, cd: cwd, timeout: @git_timeout) do
      {:ok, output} ->
        {:ok, output |> String.split("\n", trim: true) |> Enum.member?(ref)}

      {:error, reason} ->
        {:error, GitError.command_failed(reason, args, node_name, field_name)}
    end
  end

  @doc """
  Returns where the branch `branch` is. The answer is `:local`, `:remote` or
  `:new`.

  A branch that is on the disk gives `:local`. A branch that is only on `origin`
  gives `:remote`. A branch that is nowhere gives `:new`. The caller uses this
  answer to choose the arguments of `git worktree add` or of `git checkout`.
  Therefore one decision serves the two commands.

  ## Equivalent Bash

      git -C /repo for-each-ref --format=%(refname) refs/heads/feature
      git -C /repo for-each-ref --format=%(refname) refs/remotes/origin/feature
  """
  @spec branch_location(
          branch :: String.t(),
          cwd :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, branch_location()} | failure()
  def branch_location(branch, cwd, node_name, field_name)
      when is_binary(branch) and is_binary(cwd) do
    with {:ok, local?} <- branch_exists?("refs/heads/#{branch}", cwd, node_name, field_name),
         {:ok, remote?} <-
           branch_exists?("refs/remotes/origin/#{branch}", cwd, node_name, field_name) do
      {:ok, location(local?, remote?)}
    end
  end

  @doc """
  Checks out the branch `branch` in the worktree at `worktree_path`.

  If the branch is on the disk, this function checks it out. If the branch is
  only on `origin`, this function makes a local branch that tracks the remote
  branch. If the branch is nowhere, this function makes the branch.

  ## Equivalent Bash

      git -C /repo/.worktrees/feature checkout feature
      git -C /repo/.worktrees/feature checkout --track origin/feature
      git -C /repo/.worktrees/feature checkout -b feature
  """
  @spec checkout_branch(
          branch :: String.t(),
          worktree_path :: String.t(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def checkout_branch(branch, worktree_path, working_directory, node_name, field_name)
      when is_binary(branch) and is_binary(worktree_path) and is_binary(working_directory) do
    with {:ok, location} <- branch_location(branch, worktree_path, node_name, field_name),
         {:ok, _output} <-
           worktree_path
           |> checkout_args(branch, location)
           |> run_command(working_directory, node_name, field_name) do
      :ok
    end
  end

  @doc """
  Fetches the remote `remote` into the repository at `working_directory`.

  ## Equivalent Bash

      git -C /repo fetch origin
  """
  @spec fetch(
          remote :: String.t(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: command_output_result()
  def fetch(remote, working_directory, node_name, field_name)
      when is_binary(remote) and is_binary(working_directory) do
    run_command(["fetch", remote], working_directory, node_name, field_name)
  end

  @doc """
  Returns whether `name` is safe to use as a managed-worktree directory name.

  For example, `valid_worktree_name?("feature")` returns `true`, while
  `valid_worktree_name?("../escape")` and `valid_worktree_name?(".")` return `false`.

  This is a Domovoy workflow capability and has no Bash equivalent.
  """
  @spec valid_worktree_name?(String.t()) :: boolean()
  def valid_worktree_name?(name) when is_binary(name) do
    Path.basename(name) == name and name not in ["", ".", ".."] and
      not String.contains?(name, ["/", "\\"])
  end

  @doc """
  Creates the parent directory for a managed worktree when it does not exist.

  For example, a worktree at `"/repo/.worktrees/feature"` ensures
  `"/repo/.worktrees"` exists and returns `:ok`. A filesystem failure returns a
  `create_worktree_directory_failed` error.

  This is a filesystem capability and has no Bash equivalent.
  """
  @spec ensure_worktree_parent(
          worktree :: map(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def ensure_worktree_parent(%{path: path}, node_name, field_name) when is_binary(path) do
    case path |> Path.dirname() |> File.mkdir_p() do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, GitError.create_worktree_directory_failed(reason, path, node_name, field_name)}
    end
  end

  @doc """
  Extracts and expands worktree paths from Git porcelain output.

  For example, `"worktree /repo\\nHEAD ...\\n"` returns `["/repo"]`; non-worktree
  porcelain lines are ignored.

  ## Equivalent Bash

      git worktree list --porcelain
  """
  @spec worktree_paths(String.t()) :: [String.t()]
  def worktree_paths(output) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn
      "worktree " <> path -> [Path.expand(path)]
      _line -> []
    end)
  end

  @doc """
  Returns the branch checked out in `working_directory`, or `"HEAD"` when the
  checkout is detached.

  For example, a repository on `"main"` returns `{:ok, "main"}`. Unlike
  `current_branch/3`, a detached HEAD is reported as the literal string
  `"HEAD"` rather than as an error, which is what callers reporting status want.

  ## Equivalent Bash

      git -C /repo rev-parse --abbrev-ref HEAD
  """
  @spec current_branch_abbrev(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: result()
  def current_branch_abbrev(working_directory, node_name, field_name)
      when is_binary(working_directory) do
    with {:ok, output} <-
           run_command(
             ["rev-parse", "--abbrev-ref", "HEAD"],
             working_directory,
             node_name,
             field_name
           ) do
      {:ok, String.trim(output)}
    end
  end

  @doc """
  Returns the working tree status of `working_directory`, one entry for each
  changed path.

  Each entry names the state of the index and the state of the working tree. It
  also keeps the raw two-character code of Git. See
  `DomovoyGitPlugin.Capabilities.StatusEntry`.

  For example, a modified `README.md` and an untracked `notes.txt` return

      {:ok,
       [
         %{path: "README.md", code: " M", index: :unmodified, worktree: :modified},
         %{path: "notes.txt", code: "??", index: :untracked, worktree: :untracked}
       ]}

  A clean tree returns `{:ok, []}`.

  ## Equivalent Bash

      git -C /repo status --porcelain
  """
  @spec status_short(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, [StatusEntriesType.entry()]} | failure()
  def status_short(working_directory, node_name, field_name) when is_binary(working_directory) do
    with {:ok, output} <-
           run_command(["status", "--porcelain"], working_directory, node_name, field_name) do
      {:ok, status_entries(output)}
    end
  end

  @doc """
  Returns the parsed diff between `working_directory`'s tracked files and `HEAD`.

  Staged and unstaged changes are both included; untracked files are not, since
  Git cannot diff what it does not track. For example, one edited file returns
  `{:ok, [%{file: "README.md", hunks: [...]}]}`, and a clean tree returns
  `{:ok, []}`.

  ## Equivalent Bash

      git -C /repo diff HEAD
  """
  @spec diff_tracked(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, [DiffParser.file_diff()]} | failure()
  def diff_tracked(working_directory, node_name, field_name) when is_binary(working_directory) do
    with {:ok, diff_text} <-
           run_command(["diff", "HEAD"], working_directory, node_name, field_name) do
      {:ok, DiffParser.parse(diff_text)}
    end
  end

  @doc """
  Returns the parsed diff between two refs.

  For example, `branch_diff("main", "feature", "/repo", "diff", :working_directory)`
  returns the changes `feature` carries that `main` does not. The refs are
  joined with `..`, so the comparison is against their merge base rather than
  the raw tips.

  ## Equivalent Bash

      git -C /repo diff main..feature
  """
  @spec branch_diff(
          base_branch :: String.t(),
          target_branch :: String.t(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, [DiffParser.file_diff()]} | failure()
  def branch_diff(base_branch, target_branch, working_directory, node_name, field_name)
      when is_binary(base_branch) and is_binary(target_branch) and is_binary(working_directory) do
    args = ["diff", "#{base_branch}..#{target_branch}"]

    with {:ok, diff_text} <- run_command(args, working_directory, node_name, field_name) do
      {:ok, DiffParser.parse(diff_text)}
    end
  end

  @doc """
  Returns the parsed diff of every untracked file in `working_directory`.

  Untracked files are listed first, then each is diffed against `/dev/null`
  individually with `git diff --no-index`, which synthesizes a `diff --git`
  header `DomovoyGitPlugin.Capabilities.DiffParser` already understands. That command
  exits `1` whenever it finds a difference, which is the expected outcome here,
  so exit code `1` is accepted alongside `0`.

  For example, one untracked `notes.txt` returns
  `{:ok, [%{file: "notes.txt", hunks: [...]}]}`. A tree with no untracked files
  returns `{:ok, []}` without running any diff.

  ## Equivalent Bash

      git -C /repo status --porcelain --untracked-files=all
      git -C /repo diff --no-index -- /dev/null notes.txt
  """
  @spec untracked_diff(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, [DiffParser.file_diff()]} | failure()
  def untracked_diff(working_directory, node_name, field_name)
      when is_binary(working_directory) do
    with {:ok, files} <- untracked_files(working_directory, node_name, field_name),
         {:ok, diff_text} <- untracked_diff_text(files, working_directory, node_name, field_name) do
      {:ok, DiffParser.parse(diff_text)}
    end
  end

  @doc """
  Lists the paths Git reports as untracked in `working_directory`.

  Directories are expanded to their individual files, so each entry can be
  diffed on its own.

  ## Equivalent Bash

      git -C /repo status --porcelain --untracked-files=all
  """
  @spec untracked_files(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, [String.t()]} | failure()
  def untracked_files(working_directory, node_name, field_name)
      when is_binary(working_directory) do
    args = ["status", "--porcelain", "--untracked-files=all"]

    with {:ok, status_output} <- run_command(args, working_directory, node_name, field_name) do
      files =
        status_output
        |> String.split("\n")
        |> Enum.flat_map(fn
          "?? " <> file -> [file]
          _line -> []
        end)

      {:ok, files}
    end
  end

  @doc """
  Returns the upstream tracking branch configured for `working_directory`.

  A branch with no upstream is the normal state of a freshly created branch
  rather than a failure, so that case returns `{:ok, nil}` instead of an error.

  ## Equivalent Bash

      git -C /repo rev-parse --abbrev-ref --symbolic-full-name @{u}
  """
  @spec upstream_branch(working_directory :: String.t()) :: {:ok, String.t() | nil}
  def upstream_branch(working_directory) when is_binary(working_directory) do
    case Shell.run("git", ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
           cd: working_directory,
           timeout: @git_timeout
         ) do
      {:ok, output} -> {:ok, String.trim(output)}
      {:error, _reason} -> {:ok, nil}
    end
  end

  @doc """
  Resolves the repository root and the shared Git directory for
  `working_directory`.

  The shared Git directory is where every worktree of a repository keeps its
  common state, so it is where Domovoy stores the base-branch record for each
  worktree it creates. Both paths come back expanded.

  ## Equivalent Bash

      git -C /repo rev-parse --show-toplevel --git-common-dir
  """
  @spec repository(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, WorktreeMetadata.repository()} | failure()
  def repository(working_directory, node_name, field_name) when is_binary(working_directory) do
    args = ["rev-parse", "--show-toplevel", "--git-common-dir"]

    with {:ok, output} <- run_command(args, working_directory, node_name, field_name) do
      case WorktreeMetadata.parse_repository(output, working_directory) do
        {:ok, repository} ->
          {:ok, repository}

        :error ->
          {:error, GitError.repository_not_resolved(working_directory, node_name, field_name)}
      end
    end
  end

  @doc """
  Lists every worktree of the repository as a parsed porcelain record.

  For example, a repository with one managed worktree returns two records: the
  main checkout first, then the worktree. The main checkout is always first,
  whichever checkout the command runs in.

  ## Equivalent Bash

      git -C /repo worktree list --porcelain
  """
  @spec worktree_records(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, [WorktreeMetadata.worktree_record()]} | failure()
  def worktree_records(working_directory, node_name, field_name)
      when is_binary(working_directory) do
    with {:ok, output} <- worktree_list(working_directory, node_name, field_name) do
      {:ok, WorktreeMetadata.parse_porcelain(output)}
    end
  end

  @doc """
  Resolves a managed worktree name to its path, branch, and recorded base
  branch.

  The path to match is built from the **main** checkout's root, taken from the
  worktree listing itself, so the lookup resolves identically from inside a
  linked worktree and from the main checkout. A worktree created by hand with
  `git worktree add` resolves with `base_branch: nil`, since only Domovoy writes
  that record.

  ## Equivalent Bash

      git -C /repo worktree list --porcelain
  """
  @spec worktree_resolve(
          worktree_name :: String.t(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, map()} | failure()
  def worktree_resolve(worktree_name, working_directory, node_name, field_name)
      when is_binary(worktree_name) and is_binary(working_directory) do
    with {:ok, repository} <- repository(working_directory, node_name, field_name),
         {:ok, records} <- worktree_records(working_directory, node_name, field_name) do
      find_worktree(records, repository, worktree_name, node_name, field_name)
    end
  end

  @doc """
  Removes a managed worktree from the repository.

  Without `force?`, Git itself refuses to remove a worktree holding uncommitted
  changes; that refusal propagates as an error rather than being pre-empted, so
  the caller sees Git's own explanation.

  ## Equivalent Bash

      git -C /repo worktree remove --force /repo/.worktrees/feature
  """
  @spec worktree_remove(
          path :: String.t(),
          force? :: boolean(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: command_output_result()
  def worktree_remove(path, force?, working_directory, node_name, field_name)
      when is_binary(path) and is_boolean(force?) and is_binary(working_directory) do
    force_arguments = if force?, do: ["--force"], else: []

    run_command(
      ["worktree", "remove"] ++ force_arguments ++ [path],
      working_directory,
      node_name,
      field_name
    )
  end

  @doc """
  Returns the parsed diff of everything a worktree changed relative to `base_branch`.

  A single `git diff <base>` — with no `..` — diffs the base against the
  **working tree**, so one call already covers commits made on the worktree's
  branch plus its staged and unstaged changes. Untracked files are collected
  separately and concatenated, the same way `diff_changes` composes its sources.

  ## Equivalent Bash

      git -C /repo/.worktrees/feature diff main
  """
  @spec worktree_diff(
          worktree_path :: String.t(),
          base_branch :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, [DiffParser.file_diff()]} | failure()
  def worktree_diff(worktree_path, base_branch, node_name, field_name)
      when is_binary(worktree_path) and is_binary(base_branch) do
    with {:ok, diff_text} <-
           run_command(["diff", base_branch], worktree_path, node_name, field_name),
         {:ok, untracked} <- untracked_diff(worktree_path, node_name, field_name) do
      {:ok, DiffParser.parse(diff_text) ++ untracked}
    end
  end

  @doc """
  Returns everything that `worktree` changed against its base branch, together
  with the identity of the worktree.

  `base_branch` names the ref to compare with. If it is `nil`, this function
  reads the `base_branch` of the worktree, which
  `DomovoyGitPlugin.Runner.WorktreeResolve` and
  `DomovoyGitPlugin.Runner.WorktreeCreate` record. If both are `nil`, this
  function gives a `git_worktree_diff_failed` error. A worktree that a person
  made by hand has no record, so for such a worktree the caller must give a
  base branch.

  The result is the map that `DomovoyGitPlugin.Type.WorktreeDiff` describes.
  `DomovoyGitPlugin.Runner.WorktreeDiff` gives that map, and
  `DomovoyGitPlugin.Runner.WorktreeDiffMarkdown` renders it.

  ## Equivalent Bash

      git -C /repo/.worktrees/feature diff main
  """
  @spec worktree_changes(
          worktree :: WorktreeType.state(),
          base_branch :: String.t() | nil,
          node_name :: Node.name()
        ) :: {:ok, WorktreeDiffType.state()} | failure()
  def worktree_changes(
        %{name: name, path: path, branch: branch} = worktree,
        base_branch,
        node_name
      )
      when is_binary(name) and is_binary(path) do
    with {:ok, base_branch} <- diff_base_branch(worktree, base_branch, node_name),
         {:ok, files} <- worktree_diff(path, base_branch, node_name, :worktree) do
      {:ok,
       %{worktree_name: name, path: path, branch: branch, base_branch: base_branch, files: files}}
    end
  end

  @doc """
  Creates a worktree at `path` on the branch `branch_name`.

  The worktree always lands on a branch, and never on a detached `HEAD`. Thus
  work done in the worktree has somewhere to land.

  This function first asks `branch_location/4` where the branch is. If the
  branch is on the disk, Git checks it out. If the branch is only on `origin`,
  Git makes a local branch that tracks the remote branch. If the branch is
  nowhere, Git makes the branch from `base_branch`. Therefore a second worktree
  for a branch that already exists does not fail.

  ## Equivalent Bash

      git -C /repo worktree add /repo/.worktrees/feature feature
      git -C /repo worktree add --track -b feature /repo/.worktrees/feature origin/feature
      git -C /repo worktree add -b feature /repo/.worktrees/feature main
  """
  @spec worktree_add(
          path :: String.t(),
          branch_name :: String.t(),
          base_branch :: String.t(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: command_output_result()
  def worktree_add(path, branch_name, base_branch, working_directory, node_name, field_name)
      when is_binary(path) and is_binary(branch_name) and is_binary(base_branch) and
             is_binary(working_directory) do
    with {:ok, location} <-
           branch_location(branch_name, working_directory, node_name, field_name) do
      path
      |> worktree_add_args(branch_name, base_branch, location)
      |> run_command(working_directory, node_name, field_name)
    end
  end

  @doc """
  Deletes a local branch outright.

  ## Equivalent Bash

      git -C /repo branch -D feature
  """
  @spec delete_branch(
          branch :: String.t(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: command_output_result()
  def delete_branch(branch, working_directory, node_name, field_name)
      when is_binary(branch) and is_binary(working_directory) do
    run_command(["branch", "-D", branch], working_directory, node_name, field_name)
  end

  @spec find_worktree(
          records :: [WorktreeMetadata.worktree_record()],
          repository :: WorktreeMetadata.repository(),
          worktree_name :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, map()} | failure()
  defp find_worktree([], _repository, worktree_name, node_name, field_name),
    do: {:error, GitError.worktree_not_registered(worktree_name, nil, node_name, field_name)}

  defp find_worktree(records, repository, worktree_name, node_name, field_name) do
    path =
      records
      |> WorktreeMetadata.main_root()
      |> WorktreeMetadata.worktree_path(worktree_name)

    case Enum.find(records, fn record -> record.path == path end) do
      nil ->
        {:error, GitError.worktree_not_registered(worktree_name, path, node_name, field_name)}

      record ->
        {:ok,
         %{
           worktree_name: worktree_name,
           path: record.path,
           branch: record.branch,
           base_branch:
             WorktreeMetadata.read_base_branch(repository.git_common_directory, worktree_name)
         }}
    end
  end

  @spec diff_base_branch(
          worktree :: WorktreeType.state(),
          base_branch :: String.t() | nil,
          node_name :: Node.name()
        ) :: {:ok, String.t()} | failure()
  defp diff_base_branch(_worktree, base_branch, _node_name)
       when is_binary(base_branch) and base_branch != "",
       do: {:ok, base_branch}

  defp diff_base_branch(%{base_branch: base_branch}, _base_branch, _node_name)
       when is_binary(base_branch) and base_branch != "",
       do: {:ok, base_branch}

  defp diff_base_branch(%{name: name}, _base_branch, node_name) do
    {:error,
     GitError.worktree_diff_failed(
       ~s(worktree "#{name}" has no recorded base branch; supply base_branch),
       node_name,
       :base_branch
     )}
  end

  @spec untracked_diff_text(
          files :: [String.t()],
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: command_output_result()
  defp untracked_diff_text(files, working_directory, node_name, field_name) do
    Enum.reduce_while(files, {:ok, ""}, fn file, {:ok, acc} ->
      args = ["diff", "--no-index", "--", "/dev/null", file]

      case run_command(args, working_directory, node_name, field_name, ok_exit_codes: [0, 1]) do
        {:ok, diff_text} -> {:cont, {:ok, acc <> diff_text}}
        {:error, %Error{}} = failure -> {:halt, failure}
      end
    end)
  end

  @spec status_entries(String.t()) :: [StatusEntriesType.entry()]
  defp status_entries(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&StatusEntry.parse/1)
  end

  @spec location(local? :: boolean(), remote? :: boolean()) :: branch_location()
  defp location(true, _remote?), do: :local
  defp location(false, true), do: :remote
  defp location(false, false), do: :new

  @spec checkout_args(
          worktree_path :: String.t(),
          branch :: String.t(),
          location :: branch_location()
        ) :: [String.t()]
  defp checkout_args(worktree_path, branch, :local),
    do: ["-C", worktree_path, "checkout", branch]

  defp checkout_args(worktree_path, branch, :remote),
    do: ["-C", worktree_path, "checkout", "--track", "origin/#{branch}"]

  defp checkout_args(worktree_path, branch, :new),
    do: ["-C", worktree_path, "checkout", "-b", branch]

  @spec worktree_add_args(
          path :: String.t(),
          branch_name :: String.t(),
          base_branch :: String.t(),
          location :: branch_location()
        ) :: [String.t()]
  defp worktree_add_args(path, branch_name, _base_branch, :local),
    do: ["worktree", "add", path, branch_name]

  defp worktree_add_args(path, branch_name, _base_branch, :remote),
    do: ["worktree", "add", "--track", "-b", branch_name, path, "origin/#{branch_name}"]

  defp worktree_add_args(path, branch_name, base_branch, :new),
    do: ["worktree", "add", "-b", branch_name, path, base_branch]
end
