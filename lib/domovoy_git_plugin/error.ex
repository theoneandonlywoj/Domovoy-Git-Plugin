defmodule DomovoyGitPlugin.Error do
  @moduledoc """
  Builds the errors of the Git plugin, each with its context.

  Every function here gives a `DomovoyCore.Error` whose `type` identifies the
  failure, so a caller can match on the type and does not need to read a
  message. A message from Git goes into `reason`. Each error of the Git plugin
  comes from this module, and `types/0` names each one.

  Each error keeps two names in its `metadata`. `node_name` is the name of the
  node that failed. `field_name` is the input field of that node that the
  failure concerns. Therefore a failure in a graph of many nodes says which
  node failed and which input it read. This follows the redaction rule of
  `DomovoyCore.Error`. An error never holds a runner input struct, a `DomovoyCore.Node`
  or a resolved value.

  ## Examples

      iex> DomovoyGitPlugin.Error.worktree_not_found("checkout_branch", :worktree)
      %DomovoyCore.Error{
        type: :worktree_not_found,
        metadata: %{node_name: "checkout_branch", field_name: :worktree}
      }
  """

  alias DomovoyCore.Node

  @types [
    :git_command_failed,
    :missing_git_input,
    :create_worktree_directory_failed,
    :git_repository_not_resolved,
    :worktree_not_registered,
    :worktree_already_exists,
    :worktree_not_found,
    :current_branch_not_found,
    :write_worktree_record_failed,
    :git_worktree_diff_failed,
    :linear_branch_name_not_found,
    :unsupported_git_operation,
    :branch_not_found,
    :remote_branch_not_found
  ]

  @typedoc "The `type` of an error that this module builds."
  @type type() ::
          :git_command_failed
          | :missing_git_input
          | :create_worktree_directory_failed
          | :git_repository_not_resolved
          | :worktree_not_registered
          | :worktree_already_exists
          | :worktree_not_found
          | :current_branch_not_found
          | :write_worktree_record_failed
          | :git_worktree_diff_failed
          | :linear_branch_name_not_found
          | :unsupported_git_operation
          | :branch_not_found
          | :remote_branch_not_found

  @typedoc "The name of the input field that an error concerns."
  @type field_name() :: atom()

  @doc """
  Returns `true` if `value` is an error type of the Git plugin.

  Use this guard to accept a type that another module read from an error.
  """
  defguard is_type(value) when value in @types

  @doc """
  Returns every error type of the Git plugin.

  Each error of the plugin comes from a function of this module. Therefore this
  list is complete.

  ## Examples

      iex> :unsupported_git_operation in DomovoyGitPlugin.Error.types()
      true

      iex> length(DomovoyGitPlugin.Error.types())
      14
  """
  @spec types() :: [type()]
  def types, do: @types

  @doc """
  Builds a `git_command_failed` error for a Git command that did not succeed.

  `reason` is the message `DomovoyCore.Shell` produced. It already says whether
  the command exited non-zero, timed out, or could not be spawned. `args` are
  the arguments of the command, without `git`.

  ## Examples

      iex> DomovoyGitPlugin.Error.command_failed(
      ...>   "command exited with status 128: fatal: not a git repository",
      ...>   ["rev-parse", "--show-toplevel"],
      ...>   "current_branch",
      ...>   :working_directory
      ...> )
      %DomovoyCore.Error{
        type: :git_command_failed,
        reason: "command exited with status 128: fatal: not a git repository",
        metadata: %{
          command: ["git", "rev-parse", "--show-toplevel"],
          node_name: "current_branch",
          field_name: :working_directory
        }
      }
  """
  @spec command_failed(
          reason :: String.t(),
          args :: [String.t()],
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def command_failed(reason, args, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :git_command_failed,
      reason: reason,
      metadata: %{command: ["git" | args], node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds a `missing_git_input` error for an input field that an operation
  needs and the node does not supply.

  A runner that cannot require a field on the input schema checks the fields of
  the operation and gives this error for the first field that is empty.

  ## Examples

      iex> DomovoyGitPlugin.Error.missing_input("checkout_branch", :branch)
      %DomovoyCore.Error{
        type: :missing_git_input,
        metadata: %{node_name: "checkout_branch", field_name: :branch}
      }
  """
  @spec missing_input(node_name :: Node.name(), field_name :: field_name()) ::
          DomovoyCore.Error.t()
  def missing_input(node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :missing_git_input,
      metadata: %{node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds a `create_worktree_directory_failed` error for a parent directory that
  the filesystem did not create.

  ## Examples

      iex> DomovoyGitPlugin.Error.create_worktree_directory_failed(
      ...>   :eacces,
      ...>   "/repo/.worktrees/feature",
      ...>   "create_worktree",
      ...>   :worktree
      ...> )
      %DomovoyCore.Error{
        type: :create_worktree_directory_failed,
        reason: :eacces,
        metadata: %{
          path: "/repo/.worktrees/feature",
          node_name: "create_worktree",
          field_name: :worktree
        }
      }
  """
  @spec create_worktree_directory_failed(
          reason :: term(),
          path :: String.t(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def create_worktree_directory_failed(reason, path, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :create_worktree_directory_failed,
      reason: reason,
      metadata: %{path: path, node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds a `git_repository_not_resolved` error when the output of Git does not
  name a repository root and a shared Git directory.

  ## Examples

      iex> DomovoyGitPlugin.Error.repository_not_resolved("/tmp/plain", "worktree_list", :working_directory)
      %DomovoyCore.Error{
        type: :git_repository_not_resolved,
        metadata: %{
          working_directory: "/tmp/plain",
          node_name: "worktree_list",
          field_name: :working_directory
        }
      }
  """
  @spec repository_not_resolved(
          working_directory :: String.t(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def repository_not_resolved(working_directory, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :git_repository_not_resolved,
      metadata: %{
        working_directory: working_directory,
        node_name: node_name,
        field_name: field_name
      }
    })
  end

  @doc """
  Builds a `worktree_not_registered` error for a name that no worktree matches.

  `path` is where the worktree would be, or `nil` when the repository reported
  no worktrees at all.

  ## Examples

      iex> DomovoyGitPlugin.Error.worktree_not_registered(
      ...>   "feature",
      ...>   "/repo/.worktrees/feature",
      ...>   "worktree_remove",
      ...>   :worktree_name
      ...> )
      %DomovoyCore.Error{
        type: :worktree_not_registered,
        metadata: %{
          worktree_name: "feature",
          path: "/repo/.worktrees/feature",
          node_name: "worktree_remove",
          field_name: :worktree_name
        }
      }
  """
  @spec worktree_not_registered(
          worktree_name :: String.t(),
          path :: String.t() | nil,
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def worktree_not_registered(worktree_name, path, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :worktree_not_registered,
      metadata: %{
        worktree_name: worktree_name,
        path: path,
        node_name: node_name,
        field_name: field_name
      }
    })
  end

  @doc """
  Builds a `worktree_already_exists` error when a path is already occupied.

  ## Examples

      iex> DomovoyGitPlugin.Error.worktree_already_exists(
      ...>   "feature",
      ...>   "/repo/.worktrees/feature",
      ...>   "worktree_create",
      ...>   :worktree_name
      ...> )
      %DomovoyCore.Error{
        type: :worktree_already_exists,
        metadata: %{
          worktree_name: "feature",
          path: "/repo/.worktrees/feature",
          node_name: "worktree_create",
          field_name: :worktree_name
        }
      }
  """
  @spec worktree_already_exists(
          worktree_name :: String.t(),
          path :: String.t(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def worktree_already_exists(worktree_name, path, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :worktree_already_exists,
      metadata: %{
        worktree_name: worktree_name,
        path: path,
        node_name: node_name,
        field_name: field_name
      }
    })
  end

  @doc """
  Builds a `worktree_not_found` error for a managed worktree that is not on
  the disk.

  ## Examples

      iex> DomovoyGitPlugin.Error.worktree_not_found("checkout_branch", :worktree)
      %DomovoyCore.Error{
        type: :worktree_not_found,
        metadata: %{node_name: "checkout_branch", field_name: :worktree}
      }
  """
  @spec worktree_not_found(node_name :: Node.name(), field_name :: field_name()) ::
          DomovoyCore.Error.t()
  def worktree_not_found(node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :worktree_not_found,
      metadata: %{node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds a `current_branch_not_found` error when Git does not name the branch
  of the checkout.

  ## Examples

      iex> DomovoyGitPlugin.Error.current_branch_not_found("current_branch", :worktree)
      %DomovoyCore.Error{
        type: :current_branch_not_found,
        metadata: %{node_name: "current_branch", field_name: :worktree}
      }
  """
  @spec current_branch_not_found(node_name :: Node.name(), field_name :: field_name()) ::
          DomovoyCore.Error.t()
  def current_branch_not_found(node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :current_branch_not_found,
      metadata: %{node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds a `write_worktree_record_failed` error for a record that Domovoy could
  not write.

  Git made the worktree. The record of that worktree did not reach the disk.

  ## Examples

      iex> DomovoyGitPlugin.Error.write_worktree_record_failed(:eacces, "bro-19", "worktree_create", :worktree_name)
      %DomovoyCore.Error{
        type: :write_worktree_record_failed,
        reason: :eacces,
        metadata: %{
          worktree_name: "bro-19",
          node_name: "worktree_create",
          field_name: :worktree_name
        }
      }
  """
  @spec write_worktree_record_failed(
          reason :: term(),
          worktree_name :: String.t(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def write_worktree_record_failed(reason, worktree_name, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :write_worktree_record_failed,
      reason: reason,
      metadata: %{worktree_name: worktree_name, node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds a `git_worktree_diff_failed` error for a diff of a worktree that the
  runner could not make.

  `reason` says why. For example, the node gave no base branch and the
  worktree has no recorded base branch.

  ## Examples

      iex> DomovoyGitPlugin.Error.worktree_diff_failed("no base branch", "worktree_diff", :base_branch)
      %DomovoyCore.Error{
        type: :git_worktree_diff_failed,
        reason: "no base branch",
        metadata: %{node_name: "worktree_diff", field_name: :base_branch}
      }
  """
  @spec worktree_diff_failed(
          reason :: term(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def worktree_diff_failed(reason, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :git_worktree_diff_failed,
      reason: reason,
      metadata: %{node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds a `linear_branch_name_not_found` error when an issue value holds no
  branch name.

  The type keeps the `linear_` prefix because the value comes from Linear. The
  Git plugin builds the error because a Git node reads that value.

  ## Examples

      iex> DomovoyGitPlugin.Error.branch_name_not_found("target_branch", :issue)
      %DomovoyCore.Error{
        type: :linear_branch_name_not_found,
        metadata: %{node_name: "target_branch", field_name: :issue}
      }
  """
  @spec branch_name_not_found(node_name :: Node.name(), field_name :: field_name()) ::
          DomovoyCore.Error.t()
  def branch_name_not_found(node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :linear_branch_name_not_found,
      metadata: %{node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds an `unsupported_git_operation` error for an `operation` value that a
  runner does not implement.

  ## Examples

      iex> DomovoyGitPlugin.Error.unsupported_operation("rebase", "git_cli", :operation)
      %DomovoyCore.Error{
        type: :unsupported_git_operation,
        metadata: %{operation: "rebase", node_name: "git_cli", field_name: :operation}
      }
  """
  @spec unsupported_operation(
          operation :: term(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def unsupported_operation(operation, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :unsupported_git_operation,
      metadata: %{operation: operation, node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds a `branch_not_found` error for a local branch that does not exist.

  `Runner.Checkout` gives this error instead of creating the branch.

  ## Examples

      iex> DomovoyGitPlugin.Error.branch_not_found("feature", "checkout", :branch_name)
      %DomovoyCore.Error{
        type: :branch_not_found,
        metadata: %{branch: "feature", node_name: "checkout", field_name: :branch_name}
      }
  """
  @spec branch_not_found(
          branch :: String.t(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def branch_not_found(branch, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :branch_not_found,
      metadata: %{branch: branch, node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds a `remote_branch_not_found` error when a remote-tracking branch does
  not exist.

  `Runner.TrackRemoteBranch` gives this error when
  `refs/remotes/<remote>/<branch>` is missing.

  ## Examples

      iex> DomovoyGitPlugin.Error.remote_branch_not_found("origin", "feature", "track", :branch_name)
      %DomovoyCore.Error{
        type: :remote_branch_not_found,
        metadata: %{
          remote: "origin",
          branch: "feature",
          node_name: "track",
          field_name: :branch_name
        }
      }
  """
  @spec remote_branch_not_found(
          remote :: String.t(),
          branch :: String.t(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def remote_branch_not_found(remote, branch, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :remote_branch_not_found,
      metadata: %{
        remote: remote,
        branch: branch,
        node_name: node_name,
        field_name: field_name
      }
    })
  end
end
