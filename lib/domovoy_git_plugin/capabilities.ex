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
  `DomovoyGitPlugin.Capabilities.DiffParser`,
  `DomovoyGitPlugin.Capabilities.DiffMarkdown` and
  `DomovoyGitPlugin.Capabilities.Conflict`.
  """

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Shell
  alias DomovoyGitPlugin.Capabilities.Conflict
  alias DomovoyGitPlugin.Capabilities.DiffParser
  alias DomovoyGitPlugin.Capabilities.StatusEntry
  alias DomovoyGitPlugin.Capabilities.WorktreeMetadata
  alias DomovoyGitPlugin.Error, as: GitError
  alias DomovoyGitPlugin.Type.Conflicts, as: ConflictsType
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType
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
  @fetch_timeout 120_000
  @editor_env [{"GIT_EDITOR", "true"}, {"VISUAL", "true"}, {"EDITOR", "true"}]

  @operation_probes [
    {"rebase-merge", :rebasing},
    {"rebase-apply", :rebasing},
    {"MERGE_HEAD", :merging},
    {"CHERRY_PICK_HEAD", :cherry_picking},
    {"REVERT_HEAD", :reverting}
  ]

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
  Checks out a local branch. Does not create the branch if it is missing.

  A missing `refs/heads/<branch>` gives a `branch_not_found` error. A dirty
  working tree fails as Git fails, with `git_command_failed`. There is no
  `--force`.

  ## Equivalent Bash

      git -C /repo checkout feature
  """
  @spec checkout(
          branch :: String.t(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def checkout(branch, working_directory, node_name, field_name)
      when is_binary(branch) and is_binary(working_directory) do
    with {:ok, exists?} <-
           branch_exists?("refs/heads/#{branch}", working_directory, node_name, field_name),
         :ok <- require_local_branch(exists?, branch, node_name, field_name),
         {:ok, _output} <-
           run_command(["checkout", branch], working_directory, node_name, field_name) do
      :ok
    end
  end

  @doc """
  Checks out a remote-tracking branch as a new local branch.

  A missing `refs/remotes/<remote>/<branch>` gives a `remote_branch_not_found`
  error. `remote` is typically `"origin"`.

  ## Equivalent Bash

      git -C /repo checkout --track origin/feature
  """
  @spec track_remote_branch(
          branch :: String.t(),
          remote :: String.t(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def track_remote_branch(branch, remote, working_directory, node_name, field_name)
      when is_binary(branch) and is_binary(remote) and is_binary(working_directory) do
    ref = "refs/remotes/#{remote}/#{branch}"

    with {:ok, exists?} <- branch_exists?(ref, working_directory, node_name, field_name),
         :ok <- require_remote_branch(exists?, remote, branch, node_name, field_name),
         {:ok, _output} <-
           run_command(
             ["checkout", "--track", "#{remote}/#{branch}"],
             working_directory,
             node_name,
             field_name
           ) do
      :ok
    end
  end

  @doc """
  Creates `branch` and checks it out.

  `start_point` is optional. When it is `nil` or empty, Git uses `HEAD`. An
  existing branch name fails as Git fails.

  ## Equivalent Bash

      git -C /repo checkout -b feature
      git -C /repo checkout -b feature main
  """
  @spec create_branch(
          branch :: String.t(),
          start_point :: String.t() | nil,
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def create_branch(branch, start_point, working_directory, node_name, field_name)
      when is_binary(branch) and is_binary(working_directory) do
    with {:ok, _output} <-
           branch
           |> create_branch_args(start_point)
           |> run_command(working_directory, node_name, field_name) do
      :ok
    end
  end

  @doc """
  Fetches the remote `remote` into the repository at `working_directory`.

  The default timeout is 120 seconds. Pass `timeout:` in `opts` to override it.
  There is no prune and no tags flag.

  ## Equivalent Bash

      git -C /repo fetch origin
  """
  @spec fetch(
          remote :: String.t(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name(),
          opts :: keyword()
        ) :: command_output_result()
  def fetch(remote, working_directory, node_name, field_name, opts \\ [])
      when is_binary(remote) and is_binary(working_directory) do
    opts = Keyword.put_new(opts, :timeout, @fetch_timeout)
    run_command(["fetch", remote], working_directory, node_name, field_name, opts)
  end

  @doc """
  Stages the given paths with `git add --`.

  An empty path list is invalid. It does not become `git add .`. There is no
  `-f`.

  ## Equivalent Bash

      git -C /repo add -- README.md lib/a.ex
  """
  @spec add(
          paths :: [String.t()],
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def add(paths, working_directory, node_name, field_name)
      when is_list(paths) and is_binary(working_directory) do
    with :ok <- require_paths(paths, node_name, field_name),
         {:ok, _output} <-
           run_command(["add", "--" | paths], working_directory, node_name, field_name) do
      :ok
    end
  end

  @doc """
  Stages every change in the working tree with `git add -A`.

  ## Equivalent Bash

      git -C /repo add -A
  """
  @spec add_all(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def add_all(working_directory, node_name, field_name) when is_binary(working_directory) do
    with {:ok, _output} <- run_command(["add", "-A"], working_directory, node_name, field_name) do
      :ok
    end
  end

  @doc """
  Creates a commit with `message`.

  Identity is the repository `user.name` and `user.email`. A missing identity
  fails as Git fails. There is no `--amend`, no `--no-verify`, and no signing
  flag.

  ## Equivalent Bash

      git -C /repo commit -m "Add the snapshot"
      git -C /repo commit --allow-empty -m "Empty"
  """
  @spec commit(
          message :: String.t(),
          allow_empty? :: boolean(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def commit(message, allow_empty?, working_directory, node_name, field_name)
      when is_binary(message) and is_boolean(allow_empty?) and is_binary(working_directory) do
    with {:ok, _output} <-
           message
           |> commit_args(allow_empty?)
           |> run_command(working_directory, node_name, field_name) do
      :ok
    end
  end

  @doc """
  Merges `ref` into the current branch.

  When `fail_on_conflict?` is true, a conflicted stop is `git_command_failed`.
  When it is false, Git exit 1 with `operation: :merging` is success.

  ## Equivalent Bash

      git -C /repo merge --no-edit feature
  """
  @spec merge(
          ref :: String.t(),
          fail_on_conflict? :: boolean(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def merge(ref, fail_on_conflict?, working_directory, node_name, field_name)
      when is_binary(ref) and is_boolean(fail_on_conflict?) and is_binary(working_directory) do
    integrate(
      ["merge", "--no-edit", ref],
      fail_on_conflict?,
      [:merging],
      working_directory,
      node_name,
      field_name
    )
  end

  @doc """
  Rebases the current branch onto `ref`.

  The rebase is not interactive. When `fail_on_conflict?` is false, Git exit 1
  with `operation: :rebasing` is success.

  ## Equivalent Bash

      git -C /repo rebase main
  """
  @spec rebase(
          ref :: String.t(),
          fail_on_conflict? :: boolean(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def rebase(ref, fail_on_conflict?, working_directory, node_name, field_name)
      when is_binary(ref) and is_boolean(fail_on_conflict?) and is_binary(working_directory) do
    integrate(
      ["rebase", ref],
      fail_on_conflict?,
      [:rebasing],
      working_directory,
      node_name,
      field_name
    )
  end

  @doc """
  Cherry-picks `ref` onto the current branch.

  When `fail_on_conflict?` is false, Git exit 1 with `operation: :cherry_picking`
  is success.

  ## Equivalent Bash

      git -C /repo cherry-pick abc123
  """
  @spec cherry_pick(
          ref :: String.t(),
          fail_on_conflict? :: boolean(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def cherry_pick(ref, fail_on_conflict?, working_directory, node_name, field_name)
      when is_binary(ref) and is_boolean(fail_on_conflict?) and is_binary(working_directory) do
    integrate(
      ["cherry-pick", ref],
      fail_on_conflict?,
      [:cherry_picking],
      working_directory,
      node_name,
      field_name
    )
  end

  @doc """
  Aborts an in-progress merge.

  ## Equivalent Bash

      git -C /repo merge --abort
  """
  @spec merge_abort(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def merge_abort(working_directory, node_name, field_name) when is_binary(working_directory) do
    finish_command(["merge", "--abort"], working_directory, node_name, field_name)
  end

  @doc """
  Aborts an in-progress rebase.

  ## Equivalent Bash

      git -C /repo rebase --abort
  """
  @spec rebase_abort(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def rebase_abort(working_directory, node_name, field_name) when is_binary(working_directory) do
    finish_command(["rebase", "--abort"], working_directory, node_name, field_name)
  end

  @doc """
  Aborts an in-progress cherry-pick.

  ## Equivalent Bash

      git -C /repo cherry-pick --abort
  """
  @spec cherry_pick_abort(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def cherry_pick_abort(working_directory, node_name, field_name)
      when is_binary(working_directory) do
    finish_command(["cherry-pick", "--abort"], working_directory, node_name, field_name)
  end

  @doc """
  Continues an in-progress merge.

  Git uses the existing `MERGE_MSG`. There is no message input. Remaining
  conflicts fail, unless `fail_on_conflict?` is false and the checkout is still
  merging.

  ## Equivalent Bash

      git -C /repo -c core.editor=true merge --continue
  """
  @spec merge_continue(
          fail_on_conflict? :: boolean(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def merge_continue(fail_on_conflict?, working_directory, node_name, field_name)
      when is_boolean(fail_on_conflict?) and is_binary(working_directory) do
    integrate(
      ["-c", "core.editor=true", "merge", "--continue"],
      fail_on_conflict?,
      [:merging],
      working_directory,
      node_name,
      field_name,
      env: @editor_env
    )
  end

  @doc """
  Continues an in-progress rebase.

  ## Equivalent Bash

      git -C /repo -c core.editor=true rebase --continue
  """
  @spec rebase_continue(
          fail_on_conflict? :: boolean(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def rebase_continue(fail_on_conflict?, working_directory, node_name, field_name)
      when is_boolean(fail_on_conflict?) and is_binary(working_directory) do
    integrate(
      ["-c", "core.editor=true", "rebase", "--continue"],
      fail_on_conflict?,
      [:rebasing],
      working_directory,
      node_name,
      field_name,
      env: @editor_env
    )
  end

  @doc """
  Continues an in-progress cherry-pick.

  ## Equivalent Bash

      git -C /repo -c core.editor=true cherry-pick --continue
  """
  @spec cherry_pick_continue(
          fail_on_conflict? :: boolean(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def cherry_pick_continue(fail_on_conflict?, working_directory, node_name, field_name)
      when is_boolean(fail_on_conflict?) and is_binary(working_directory) do
    integrate(
      ["-c", "core.editor=true", "cherry-pick", "--continue"],
      fail_on_conflict?,
      [:cherry_picking],
      working_directory,
      node_name,
      field_name,
      env: @editor_env
    )
  end

  @doc """
  Checks out the `--ours` stage of the given paths. Does not `git add`.

  ## Equivalent Bash

      git -C /repo checkout --ours -- README.md
  """
  @spec checkout_ours(
          paths :: [String.t()],
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def checkout_ours(paths, working_directory, node_name, field_name)
      when is_list(paths) and is_binary(working_directory) do
    checkout_stage("--ours", paths, working_directory, node_name, field_name)
  end

  @doc """
  Checks out the `--theirs` stage of the given paths. Does not `git add`.

  ## Equivalent Bash

      git -C /repo checkout --theirs -- README.md
  """
  @spec checkout_theirs(
          paths :: [String.t()],
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def checkout_theirs(paths, working_directory, node_name, field_name)
      when is_list(paths) and is_binary(working_directory) do
    checkout_stage("--theirs", paths, working_directory, node_name, field_name)
  end

  @doc """
  Fetches `remote` and then merges or rebases the fetched ref.

  This is fetch plus merge or rebase, not `git pull`, so conflict policy is one
  code path. The fetch timeout is 120 seconds. `refspec` is optional. When it is
  missing, the tracking ref `remote/current-branch` is merged or rebased.

  ## Equivalent Bash

      git -C /repo fetch origin
      git -C /repo merge --no-edit origin/main
  """
  @spec pull(
          remote :: String.t(),
          refspec :: String.t() | nil,
          rebase? :: boolean(),
          fail_on_conflict? :: boolean(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def pull(remote, refspec, rebase?, fail_on_conflict?, working_directory, node_name, field_name)
      when is_binary(remote) and is_boolean(rebase?) and is_boolean(fail_on_conflict?) and
             is_binary(working_directory) do
    with {:ok, _output} <-
           fetch_ref(remote, refspec, working_directory, node_name, field_name),
         {:ok, target} <-
           pull_target(remote, refspec, working_directory, node_name, field_name) do
      integrate_pull(target, rebase?, fail_on_conflict?, working_directory, node_name, field_name)
    end
  end

  @doc """
  Pushes to `remote`.

  There is no `--force` and no `--force-with-lease`. `refspec` is optional. When
  it is missing and `set_upstream?` is false, Git uses the configured upstream
  and fails if there is none. The timeout is 120 seconds.

  ## Equivalent Bash

      git -C /repo push origin
      git -C /repo push -u origin feature
  """
  @spec push(
          remote :: String.t(),
          refspec :: String.t() | nil,
          set_upstream? :: boolean(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  def push(remote, refspec, set_upstream?, working_directory, node_name, field_name)
      when is_binary(remote) and is_boolean(set_upstream?) and is_binary(working_directory) do
    with {:ok, args} <-
           push_args(remote, refspec, set_upstream?, working_directory, node_name, field_name),
         {:ok, _output} <-
           run_command(args, working_directory, node_name, field_name, timeout: @fetch_timeout) do
      :ok
    end
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
  Returns a snapshot of the checkout at `working_directory`.

  That directory may be the main worktree or a linked worktree. `path` is this
  checkout. `repo_root` is the first record of `git worktree list --porcelain`,
  which is the main checkout. Domovoy's JSON under the git-common-dir names
  `base_branch`. Unmanaged worktrees and the main checkout give `nil`.

  Operation detection inspects Git state files through `git rev-parse --git-path`.
  That is correct inside a worktree. A rebase counts through its state
  directory. `REBASE_HEAD` alone is a leftover that Git keeps after a completed
  rebase. When more than one state exists, the order is rebase, then merge,
  then cherry-pick, then revert.

  A merge that finished resolving but is not committed still has `MERGE_HEAD`.
  Then `operation` is `:merging` and `conflicts` is `[]`. That pair is data, not
  an error.

  ## Equivalent Bash

      git -C /repo rev-parse --show-toplevel
      git -C /repo worktree list --porcelain
      git -C /repo status --porcelain
  """
  @spec repo_state(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, RepoStateType.state()} | failure()
  def repo_state(working_directory, node_name, field_name) when is_binary(working_directory) do
    with {:ok, repository} <- repository(working_directory, node_name, field_name),
         {:ok, records} <- worktree_records(working_directory, node_name, field_name),
         {:ok, repo_root} <- main_checkout(records, working_directory, node_name, field_name),
         {:ok, {current_branch, detached?}} <-
           current_branch_state(working_directory, node_name, field_name),
         {:ok, upstream_branch} <- upstream_branch(working_directory),
         {:ok, {ahead, behind}} <- ahead_behind(working_directory, node_name, field_name),
         {:ok, status} <- status_short(working_directory, node_name, field_name),
         {:ok, operation} <- operation(working_directory, node_name, field_name),
         {:ok, conflicts} <-
           conflicts_from_status(status, working_directory, node_name, field_name) do
      path = repository.root
      checkout = if path == repo_root, do: :main, else: :worktree
      worktree_name = if checkout == :worktree, do: Path.basename(path), else: nil

      {:ok,
       %{
         path: path,
         repo_root: repo_root,
         checkout: checkout,
         worktree_name: worktree_name,
         base_branch: recorded_base_branch(repository.git_common_directory, worktree_name),
         current_branch: current_branch,
         detached?: detached?,
         upstream_branch: upstream_branch,
         ahead: ahead,
         behind: behind,
         dirty?: status != [],
         operation: operation,
         status: status,
         conflicts: conflicts
       }}
    end
  end

  @doc """
  Returns the in-progress Git operation of the checkout at `working_directory`.

  Detection uses `git rev-parse --git-path` so it is correct inside a worktree.
  A rebase counts when the `rebase-merge` or the `rebase-apply` directory
  exists. `REBASE_HEAD` alone does not count, since Git leaves that file behind
  after a completed rebase. When more than one state exists, the order is
  rebase, then merge, then cherry-pick, then revert.

  ## Equivalent Bash

      git -C /repo rev-parse --git-path MERGE_HEAD
  """
  @spec operation(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, RepoStateType.operation()} | failure()
  def operation(working_directory, node_name, field_name) when is_binary(working_directory) do
    args = Enum.flat_map(@operation_probes, fn {path, _operation} -> ["--git-path", path] end)

    with {:ok, output} <-
           run_command(["rev-parse" | args], working_directory, node_name, field_name) do
      {:ok, detect_operation(output, working_directory)}
    end
  end

  @doc """
  Returns how far `HEAD` is ahead of and behind its upstream.

  When there is no upstream, both numbers are `nil`. Detached HEAD has no
  upstream.

  ## Equivalent Bash

      git -C /repo rev-list --left-right --count HEAD...@{u}
  """
  @spec ahead_behind(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, {non_neg_integer() | nil, non_neg_integer() | nil}} | failure()
  def ahead_behind(working_directory, node_name, field_name) when is_binary(working_directory) do
    with {:ok, upstream} <- upstream_branch(working_directory) do
      count_ahead_behind(upstream, working_directory, node_name, field_name)
    end
  end

  @doc """
  Returns the unmerged paths of the checkout at `working_directory`.

  Porcelain names the kind. `git ls-files -u` names the stages. Conflict
  markers in the working-tree file name the hunks. An empty list means there
  are no unmerged paths. That is success, not an error.

  ## Equivalent Bash

      git -C /repo status --porcelain
      git -C /repo ls-files -u
  """
  @spec conflicts(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, [ConflictsType.conflict()]} | failure()
  def conflicts(working_directory, node_name, field_name) when is_binary(working_directory) do
    with {:ok, status} <- status_short(working_directory, node_name, field_name) do
      conflicts_from_status(status, working_directory, node_name, field_name)
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

  @spec require_local_branch(
          exists? :: boolean(),
          branch :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  defp require_local_branch(true, _branch, _node_name, _field_name), do: :ok

  defp require_local_branch(false, branch, node_name, field_name),
    do: {:error, GitError.branch_not_found(branch, node_name, field_name)}

  @spec require_remote_branch(
          exists? :: boolean(),
          remote :: String.t(),
          branch :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  defp require_remote_branch(true, _remote, _branch, _node_name, _field_name), do: :ok

  defp require_remote_branch(false, remote, branch, node_name, field_name),
    do: {:error, GitError.remote_branch_not_found(remote, branch, node_name, field_name)}

  @spec create_branch_args(branch :: String.t(), start_point :: String.t() | nil) :: [String.t()]
  defp create_branch_args(branch, start_point)
       when is_binary(start_point) and start_point != "",
       do: ["checkout", "-b", branch, start_point]

  defp create_branch_args(branch, _start_point), do: ["checkout", "-b", branch]

  @spec main_checkout(
          records :: [WorktreeMetadata.worktree_record()],
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, String.t()} | failure()
  defp main_checkout([], working_directory, node_name, field_name),
    do: {:error, GitError.repository_not_resolved(working_directory, node_name, field_name)}

  defp main_checkout(records, _working_directory, _node_name, _field_name),
    do: {:ok, WorktreeMetadata.main_root(records)}

  @spec current_branch_state(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, {String.t() | nil, boolean()}} | failure()
  defp current_branch_state(working_directory, node_name, field_name) do
    with {:ok, output} <-
           run_command(["branch", "--show-current"], working_directory, node_name, field_name) do
      case String.trim(output) do
        "" -> {:ok, {nil, true}}
        branch -> {:ok, {branch, false}}
      end
    end
  end

  @spec recorded_base_branch(
          git_common_directory :: String.t(),
          worktree_name :: String.t() | nil
        ) ::
          String.t() | nil
  defp recorded_base_branch(_git_common_directory, nil), do: nil

  defp recorded_base_branch(git_common_directory, worktree_name),
    do: WorktreeMetadata.read_base_branch(git_common_directory, worktree_name)

  @spec detect_operation(output :: String.t(), working_directory :: String.t()) ::
          RepoStateType.operation()
  defp detect_operation(output, working_directory) do
    paths = String.split(output, "\n", trim: true)

    @operation_probes
    |> Enum.zip(paths)
    |> Enum.find_value(:idle, fn {{_name, operation}, path} ->
      if path |> Path.expand(working_directory) |> File.exists?(), do: operation
    end)
  end

  @spec count_ahead_behind(
          upstream :: String.t() | nil,
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, {non_neg_integer() | nil, non_neg_integer() | nil}} | failure()
  defp count_ahead_behind(nil, _working_directory, _node_name, _field_name), do: {:ok, {nil, nil}}

  defp count_ahead_behind(_upstream, working_directory, node_name, field_name) do
    args = ["rev-list", "--left-right", "--count", "HEAD...@{u}"]

    with {:ok, output} <- run_command(args, working_directory, node_name, field_name) do
      parse_ahead_behind(output)
    end
  end

  @spec parse_ahead_behind(output :: String.t()) ::
          {:ok, {non_neg_integer() | nil, non_neg_integer() | nil}}
  defp parse_ahead_behind(output) do
    case output |> String.trim() |> String.split("\t") do
      [ahead, behind] ->
        with {ahead, ""} <- Integer.parse(ahead),
             {behind, ""} <- Integer.parse(behind),
             true <- ahead >= 0 and behind >= 0 do
          {:ok, {ahead, behind}}
        else
          _other -> {:ok, {nil, nil}}
        end

      _other ->
        {:ok, {nil, nil}}
    end
  end

  @spec conflicts_from_status(
          status :: [StatusEntriesType.entry()],
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, [ConflictsType.conflict()]} | failure()
  defp conflicts_from_status(status, working_directory, node_name, field_name) do
    with {:ok, output} <-
           run_command(["ls-files", "-u"], working_directory, node_name, field_name) do
      stages_by_path = Conflict.parse_stages(output)

      conflicts =
        status
        |> Enum.filter(&Conflict.unmerged?/1)
        |> Enum.map(fn entry ->
          Conflict.conflict(
            entry,
            Map.get(stages_by_path, entry.path, Conflict.empty_stages()),
            working_directory
          )
        end)

      {:ok, conflicts}
    end
  end

  @spec require_paths(
          paths :: [String.t()],
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  defp require_paths([], node_name, field_name),
    do: {:error, GitError.missing_input(node_name, field_name)}

  defp require_paths(paths, _node_name, _field_name) when is_list(paths), do: :ok

  @spec commit_args(message :: String.t(), allow_empty? :: boolean()) :: [String.t()]
  defp commit_args(message, true), do: ["commit", "--allow-empty", "-m", message]
  defp commit_args(message, false), do: ["commit", "-m", message]

  @spec finish_command(
          args :: [String.t()],
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  defp finish_command(args, working_directory, node_name, field_name) do
    with {:ok, _output} <- run_command(args, working_directory, node_name, field_name) do
      :ok
    end
  end

  @spec integrate(
          args :: [String.t()],
          fail_on_conflict? :: boolean(),
          operations :: [RepoStateType.operation()],
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name(),
          opts :: keyword()
        ) :: :ok | failure()
  defp integrate(
         args,
         fail_on_conflict?,
         operations,
         working_directory,
         node_name,
         field_name,
         opts \\ []
       ) do
    case run_command(args, working_directory, node_name, field_name, opts) do
      {:ok, _output} ->
        :ok

      {:error, error} ->
        accept_conflicted_stop(
          error,
          fail_on_conflict?,
          operations,
          working_directory,
          node_name,
          field_name
        )
    end
  end

  @spec accept_conflicted_stop(
          error :: Error.t(),
          fail_on_conflict? :: boolean(),
          operations :: [RepoStateType.operation()],
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  defp accept_conflicted_stop(
         error,
         true,
         _operations,
         _working_directory,
         _node_name,
         _field_name
       ),
       do: {:error, error}

  defp accept_conflicted_stop(error, false, operations, working_directory, node_name, field_name) do
    case operation(working_directory, node_name, field_name) do
      {:ok, operation} ->
        if operation in operations, do: :ok, else: {:error, error}

      {:error, _reason} ->
        {:error, error}
    end
  end

  @spec checkout_stage(
          stage :: String.t(),
          paths :: [String.t()],
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  defp checkout_stage(stage, paths, working_directory, node_name, field_name) do
    with :ok <- require_paths(paths, node_name, field_name),
         {:ok, _output} <-
           run_command(
             ["checkout", stage, "--" | paths],
             working_directory,
             node_name,
             field_name
           ) do
      :ok
    end
  end

  @spec fetch_ref(
          remote :: String.t(),
          refspec :: String.t() | nil,
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: command_output_result()
  defp fetch_ref(remote, refspec, working_directory, node_name, field_name)
       when is_binary(refspec) and refspec != "" do
    run_command(["fetch", remote, refspec], working_directory, node_name, field_name,
      timeout: @fetch_timeout
    )
  end

  defp fetch_ref(remote, _refspec, working_directory, node_name, field_name) do
    fetch(remote, working_directory, node_name, field_name)
  end

  @spec pull_target(
          remote :: String.t(),
          refspec :: String.t() | nil,
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, String.t()} | failure()
  defp pull_target(_remote, refspec, _working_directory, _node_name, _field_name)
       when is_binary(refspec) and refspec != "",
       do: {:ok, "FETCH_HEAD"}

  defp pull_target(remote, _refspec, working_directory, node_name, field_name) do
    with {:ok, branch} <- current_branch(working_directory, node_name, field_name) do
      {:ok, "#{remote}/#{branch}"}
    end
  end

  @spec integrate_pull(
          target :: String.t(),
          rebase? :: boolean(),
          fail_on_conflict? :: boolean(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: :ok | failure()
  defp integrate_pull(target, true, fail_on_conflict?, working_directory, node_name, field_name),
    do: rebase(target, fail_on_conflict?, working_directory, node_name, field_name)

  defp integrate_pull(target, false, fail_on_conflict?, working_directory, node_name, field_name),
    do: merge(target, fail_on_conflict?, working_directory, node_name, field_name)

  @spec push_args(
          remote :: String.t(),
          refspec :: String.t() | nil,
          set_upstream? :: boolean(),
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: GitError.field_name()
        ) :: {:ok, [String.t()]} | failure()
  defp push_args(remote, refspec, true, _working_directory, _node_name, _field_name)
       when is_binary(refspec) and refspec != "",
       do: {:ok, ["push", "-u", remote, refspec]}

  defp push_args(remote, refspec, false, _working_directory, _node_name, _field_name)
       when is_binary(refspec) and refspec != "",
       do: {:ok, ["push", remote, refspec]}

  defp push_args(remote, _refspec, true, working_directory, node_name, field_name) do
    with {:ok, branch} <- current_branch(working_directory, node_name, field_name) do
      {:ok, ["push", "-u", remote, branch]}
    end
  end

  defp push_args(remote, _refspec, false, _working_directory, _node_name, _field_name),
    do: {:ok, ["push", remote]}

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
